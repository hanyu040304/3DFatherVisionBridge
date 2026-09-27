"""Run with python3 -m unittest discover -s Tests -v; Fusion API is mocked."""
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import threading
import time
import types
import unittest
import zipfile

class Event:
    def __init__(self): self.handlers = []
    def add(self, h): self.handlers.append(h); return True
    def remove(self, h): self.handlers.remove(h); return True
    def emit(self, args):
        for h in list(self.handlers): h.notify(args)

class App:
    def __init__(self):
        self.events = {}; self.queue = []; self.exports = 0; self.fail = False
        self.component = types.SimpleNamespace(entityToken='root', revisionId='r1')
        components = types.SimpleNamespace(count=1, item=lambda index: self.component)
        self.activeProduct = types.SimpleNamespace(exportManager=self, rootComponent=self.component, allComponents=components)
        self.userInterface = types.SimpleNamespace(commandTerminated=Event())
        self.documentActivated = Event()
    def log(self, message): pass
    def registerCustomEvent(self, key): self.events[key] = Event(); return self.events[key]
    def unregisterCustomEvent(self, key): del self.events[key]
    def fireCustomEvent(self, key, info): self.queue.append((key, info)); return True
    def drain(self):
        while self.queue:
            key, info = self.queue.pop(0)
            if key in self.events: self.events[key].emit(types.SimpleNamespace(additionalInfo=info))
    def createUSDExportOptions(self, filename, geometry): return filename
    def execute(self, filename):
        assert threading.current_thread() is threading.main_thread()
        self.exports += 1
        with zipfile.ZipFile(filename + '.usdz', 'w') as z: z.writestr('model.usdc', 'model')
        return not self.fail

class ManualExportTests(unittest.TestCase):
    def setUp(self):
        self.app = App()
        core = types.ModuleType('adsk.core')
        core.CustomEventHandler = core.ApplicationCommandEventHandler = core.DocumentEventHandler = object
        core.Application = types.SimpleNamespace(get=lambda: self.app)
        fusion = types.ModuleType('adsk.fusion')
        fusion.Design = types.SimpleNamespace(cast=lambda x: x)
        adsk = types.ModuleType('adsk'); adsk.core = core; adsk.fusion = fusion
        sys.modules.update({'adsk': adsk, 'adsk.core': core, 'adsk.fusion': fusion})
        spec = importlib.util.spec_from_file_location('manual_addin', Path(__file__).resolve().parents[1]/'FusionAddin/FusionSpatialLive.py')
        self.m = importlib.util.module_from_spec(spec); spec.loader.exec_module(self.m)
        self.temp = tempfile.TemporaryDirectory(); self.root = Path(self.temp.name)
        self.m._directory = self.root
        self.m.run(None)
    def tearDown(self): self.m.stop(None); self.temp.cleanup()
    def request(self, identity='one', expires=None):
        (self.root/'export-request.json').write_text(json.dumps({'id': identity, 'expiresAt': expires or time.time()+10}))
        time.sleep(.65); self.app.drain()
    def response(self): return json.loads((self.root/'export-response.json').read_text())
    def test_no_automatic_export(self):
        self.app.userInterface.commandTerminated.emit(None)
        self.app.documentActivated.emit(None)
        time.sleep(.65); self.app.drain()
        self.assertEqual(self.app.exports, 0)
    def test_click_exports_once_and_acknowledges(self):
        self.request()
        self.assertEqual(self.app.exports, 1)
        self.assertEqual(self.response()['id'], 'one')
        self.assertEqual(self.response()['status'], 'complete')
        self.assertTrue(zipfile.is_zipfile(self.root/'current.usdz'))
        time.sleep(.65); self.app.drain()
        self.assertEqual(self.app.exports, 1)
        self.request('two'); self.assertEqual(self.app.exports, 2)
    def test_model_change_marks_dirty_without_exporting(self):
        notice = self.root/'model-change.json'
        original = notice.read_text()
        self.app.userInterface.commandTerminated.emit(None)
        self.assertEqual(notice.read_text(), original)
        self.app.component.revisionId = 'r2'
        self.app.userInterface.commandTerminated.emit(None)
        self.assertNotEqual(notice.read_text(), original)
        self.assertEqual(self.app.exports, 0)

    def test_heartbeat_and_exclusive_connector(self):
        time.sleep(.25)
        status = json.loads((self.root/'connector-status.json').read_text())
        self.assertEqual(status['version'], '1.2.0')
        spec = importlib.util.spec_from_file_location('duplicate_addin', Path(self.m.__file__))
        duplicate = importlib.util.module_from_spec(spec); spec.loader.exec_module(duplicate)
        duplicate._directory = self.root
        duplicate.run(None)
        self.assertFalse(duplicate._running)
        duplicate.stop(None)
        self.assertTrue(self.m._running)
        self.assertEqual(len(self.app.events), 1)

    def test_duplicate_delivery_exports_only_once(self):
        self.request()
        request = (self.root/'export-request.json').read_text()
        event = next(iter(self.app.events.values()))
        event.emit(types.SimpleNamespace(additionalInfo=request))
        event.emit(types.SimpleNamespace(additionalInfo=request))
        self.assertEqual(self.app.exports, 1)
        self.assertEqual(self.response()['status'], 'complete')

    def test_failure_keeps_previous_model(self):
        current=self.root/'current.usdz'; current.write_bytes(b'previous')
        self.app.fail=True; self.request()
        self.assertEqual(current.read_bytes(), b'previous')
        self.assertEqual(self.response()['status'], 'error')
    def test_missing_design_reports_error(self):
        self.app.activeProduct=None; self.request()
        self.assertEqual(self.response()['status'], 'error')
        self.assertEqual(self.app.exports, 0)
    def test_expired_request_and_stop_do_not_export(self):
        self.request(expires=time.time()-10)
        self.assertEqual(self.app.exports, 0)
        self.m.stop(None); self.request('after-stop')
        self.assertEqual(self.app.exports, 0)
        self.assertFalse(self.app.events)

if __name__ == '__main__': unittest.main()
