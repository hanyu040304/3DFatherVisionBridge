"""Export once per explicit Mac app request; all Fusion work stays on its main thread."""
import fcntl
import json
import os
from pathlib import Path
import threading
import time
import uuid
import zipfile

import adsk.core
import adsk.fusion

_app = None
_event = None
_handler = None
_event_id = None
_worker = None
_stop_event = None
_running = False
_handled_request = None
_directory = Path.home() / 'Library' / 'Application Support' / 'FusionSpatialBridge' / 'Bridge'
_version = json.loads(Path(__file__).with_suffix('.manifest').read_text(encoding='utf-8'))['version']
_installation_id = 'development'
_lock_file = None
_change_handlers = []
_exporting = False
_last_revision = None



def _respond(request_id, status, message='', timings=None):
    pending = _directory / 'export-response.tmp'
    pending.write_text(json.dumps({'id': request_id, 'status': status, 'message': message, 'timings': timings}), encoding='utf-8')
    os.replace(pending, _directory / 'export-response.json')


def _export(request_id, timings):
    global _exporting
    _exporting = True
    started = time.perf_counter()
    temporary = _directory / 'current_tmp.usd'
    package = Path(str(temporary) + '.usdz')
    try:
        design = adsk.fusion.Design.cast(_app.activeProduct)
        if not design:
            raise RuntimeError('请先在 Fusion 中打开一个设计')
        _respond(request_id, 'exporting')
        _app.log('[FusionSpatial] Exporting...')
        temporary.unlink(missing_ok=True)
        package.unlink(missing_ok=True)
        manager = design.exportManager
        options = manager.createUSDExportOptions(str(temporary), design.rootComponent)
        if not options or not manager.execute(options):
            raise RuntimeError('Fusion USDZ 导出失败')
        timings['exportSeconds'] = time.perf_counter() - started
        validation_started = time.perf_counter()
        source = package if package.is_file() else temporary
        if not source.is_file() or not zipfile.is_zipfile(source):
            raise RuntimeError('Fusion 未生成有效的 USDZ 文件')
        with zipfile.ZipFile(source) as archive:
            if not archive.infolist() or archive.testzip() is not None:
                raise RuntimeError('Fusion USDZ 文件为空或损坏')
        os.replace(source, _directory / 'current.usdz')
        timings['fileSeconds'] = time.perf_counter() - validation_started
        timings['bytes'] = (_directory / 'current.usdz').stat().st_size
        _respond(request_id, 'complete', timings=timings)
        _app.log('[FusionSpatial] Timings: ' + json.dumps(timings))
        _app.log('[FusionSpatial] Export completed')
    except Exception as error:
        _app.log('[FusionSpatial] Export failed: ' + str(error))
        _respond(request_id, 'error', str(error))
    finally:
        _exporting = False


def _poll_requests(app, event_id, stop_event):
    # Only lightweight file reads here. fireCustomEvent queues work on Fusion's
    # main thread; the worker never reads a design or invokes the exporter.
    last_request = None
    last_heartbeat = 0
    while not stop_event.wait(0.1):
        try:
            if time.monotonic() - last_heartbeat > 2:
                pending = _directory / 'connector-status.tmp'
                pending.write_text(json.dumps({'version': _version, 'installationID': _installation_id,
                    'timestamp': time.time(), 'pid': os.getpid()}), encoding='utf-8')
                os.replace(pending, _directory / 'connector-status.json')
                last_heartbeat = time.monotonic()
            request = json.loads((_directory / 'export-request.json').read_text(encoding='utf-8'))
            request_id = request['id']
            if not isinstance(request_id, str) or not request_id or request_id == last_request:
                continue
            if float(request['expiresAt']) < time.time():
                last_request = request_id
                continue
            # Claim BEFORE enqueueing. Some live dispatch paths can redeliver;
            # notify also deduplicates before entering the synchronous exporter.
            request['detectedAt'] = time.time()
            last_request = request_id
            if app.fireCustomEvent(event_id, json.dumps(request)) is False:
                last_request = None
        except (OSError, ValueError, KeyError, TypeError):
            continue
        except Exception as error:
            print('[FusionSpatial] Request failed: ' + str(error))


class ExportHandler(adsk.core.CustomEventHandler):
    def notify(self, args):
        global _handled_request
        if not _running:
            return
        try:
            request = json.loads(args.additionalInfo)
            # Discard requests superseded or expired while Fusion was busy.
            current = json.loads((_directory / 'export-request.json').read_text(encoding='utf-8'))
            if request['id'] != current['id'] or float(request['expiresAt']) < time.time():
                return
            if request['id'] == _handled_request:
                return
            # Also reject a completed request after an add-in reload.
            try:
                response = json.loads((_directory / 'export-response.json').read_text(encoding='utf-8'))
                if response.get('id') == request['id'] and response.get('status') in ('complete', 'error'):
                    _handled_request = request['id']
                    return
            except (OSError, ValueError):
                pass
            _handled_request = request['id']
            now = time.time()
            detected = request.get('detectedAt', now)
            timings = {
                'detectionSeconds': max(0, detected - request.get('requestedAt', detected)),
                'queueSeconds': max(0, now - detected)
            }
            _export(request['id'], timings)
        except Exception as error:
            _app.log('[FusionSpatial] Request failed: ' + str(error))


def _notify_model_change():
    global _last_revision
    if not _running or _exporting:
        return
    try:
        design = adsk.fusion.Design.cast(_app.activeProduct)
        if not design:
            return
        # Revision IDs avoid triggering an export for camera and selection commands.
        components = design.allComponents
        revision = tuple(components.item(i).revisionId for i in range(components.count))
        if revision == _last_revision:
            return
        _last_revision = revision
        pending = _directory / 'model-change.tmp'
        pending.write_text(json.dumps({'id': uuid.uuid4().hex, 'timestamp': time.time()}), encoding='utf-8')
        os.replace(pending, _directory / 'model-change.json')
    except Exception:
        # Manual updates still work for unsupported/non-design products.
        pass


class ModelCommandHandler(adsk.core.ApplicationCommandEventHandler):
    def notify(self, args):
        _notify_model_change()


class ModelDocumentHandler(adsk.core.DocumentEventHandler):
    def notify(self, args):
        _notify_model_change()


def run(context):
    global _app, _event, _handler, _event_id, _worker, _stop_event, _running, _lock_file, _installation_id
    if _running:
        return
    _app = adsk.core.Application.get()
    try:
        _directory.mkdir(parents=True, exist_ok=True)
        _lock_file = (_directory / '.connector.lock').open('a')
        try:
            fcntl.flock(_lock_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            _lock_file.close()
            _lock_file = None
            _app.log('[FusionSpatial] warning: another connector instance is already active')
            return
        receipt = Path(__file__).with_name('installed.json')
        if receipt.is_file():
            _installation_id = json.loads(receipt.read_text(encoding='utf-8'))['installationID']
        _event_id = 'FusionSpatialLive.' + uuid.uuid4().hex
        _event = _app.registerCustomEvent(_event_id)
        _handler = ExportHandler()
        if not _event.add(_handler):
            raise RuntimeError('Cannot register export handler')
        _running = True
        _stop_event = threading.Event()
        _worker = threading.Thread(target=_poll_requests, args=(_app, _event_id, _stop_event), daemon=True)
        _worker.start()
        for event, handler in [(_app.userInterface.commandTerminated, ModelCommandHandler()),
                               (_app.documentActivated, ModelDocumentHandler())]:
            if event.add(handler):
                _change_handlers.append((event, handler))
        _notify_model_change()
        _app.log('[FusionSpatial] start: connector ' + _version)
    except Exception as error:
        _app.log('[FusionSpatial] Start failed: ' + str(error))
        stop(context)


def stop(context):
    global _running, _event, _handler, _event_id, _worker, _stop_event, _lock_file
    _running = False
    if _stop_event:
        _stop_event.set()
    if _worker:
        _worker.join()
        _worker = None
    for event, handler in _change_handlers:
        event.remove(handler)
    _change_handlers.clear()
    if _lock_file:
        _lock_file.close()
        _lock_file = None
    if _event and _handler:
        _event.remove(_handler)
    if _app and _event_id:
        _app.unregisterCustomEvent(_event_id)
    _event = _handler = _event_id = _stop_event = None
