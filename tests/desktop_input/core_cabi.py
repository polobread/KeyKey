"""Owned UTF-8 JSON calls to the portable Guanyinma C ABI; no desktop UI."""
import ctypes as C, json, os
from pathlib import Path
LIB = Path(os.environ['GUANYINMA_TEST_LIBRARY'])
MODEL = Path(os.environ['GUANYINMA_TEST_MODEL'])

class Session:

    def __init__(self, configuration):
        self.lib = C.CDLL(str(LIB))
        self.session = C.c_void_p()
        self.committed = ''
        for name, types in [('guanyinma_session_open', [C.c_char_p, C.c_size_t, C.c_char_p, C.c_size_t, C.POINTER(C.c_void_p)]), ('guanyinma_session_apply', [C.c_void_p, C.c_char_p, C.c_size_t, C.POINTER(C.c_void_p)]), ('guanyinma_session_snapshot', [C.c_void_p, C.POINTER(C.c_void_p)]), ('guanyinma_result_json', [C.c_void_p, C.c_void_p, C.c_size_t, C.POINTER(C.c_size_t)]), ('guanyinma_result_close', [C.POINTER(C.c_void_p)]), ('guanyinma_session_close', [C.POINTER(C.c_void_p)])]:
            getattr(self.lib, name).argtypes = types
            getattr(self.lib, name).restype = C.c_int32
        cfg = {'profile': 'desktop', 'learning': {'user_phrases': False, 'candidate_overrides': False, 'bigrams': False, 'table_learning': False}, **configuration}
        data = json.dumps(cfg).encode()
        path = str(MODEL).encode()
        code = self.lib.guanyinma_session_open(path, len(path), data, len(data), C.byref(self.session))
        assert code == 0, ('open', code, cfg)

    def result(self, r):
        try:
            n = C.c_size_t()
            self.lib.guanyinma_result_json(r, None, 0, C.byref(n))
            buf = C.create_string_buffer(n.value)
            code = self.lib.guanyinma_result_json(r, buf, n.value, C.byref(n))
            assert code == 0, code
            return json.loads(buf.value)
        finally:
            self.lib.guanyinma_result_close(C.byref(r))

    def apply(self, operation):
        data = json.dumps(operation).encode()
        r = C.c_void_p()
        code = self.lib.guanyinma_session_apply(self.session, data, len(data), C.byref(r))
        assert code == 0, ('apply', code, operation)
        v = self.result(r)
        self.committed += v['effects']['commit']
        return v

    def type(self, text):
        for c in text:
            v = self.apply({'type': 'character', 'text': c})
        return v

    def key(self, key):
        return self.apply({'type': 'key', 'key': key})

    def close(self):
        self.lib.guanyinma_session_close(C.byref(self.session))
