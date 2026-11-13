"""Reads Lua table literals as data (no Lua is executed).

Polestar's compiled guide files are Lua source; this extracts the table passed to
each Polestar.RegisterGuide({...}) call and parses it into Python dicts/lists.
Identifiers and indexed references (candidateLists[1]) become {"ref": text}.
"""
import re

_num = re.compile(r'-?(?:0x[0-9a-fA-F]+|\d+\.?\d*(?:[eE][-+]?\d+)?|\.\d+)')
_ident = re.compile(r'[A-Za-z_][A-Za-z0-9_]*')
_ESC = {'n': '\n', 't': '\t', 'r': '\r', '\\': '\\', '"': '"', "'": "'", 'a': '\a', 'b': '\b', 'f': '\f', 'v': '\v', '\n': '\n'}


class Parser:
    def __init__(self, s, i=0):
        self.s, self.i = s, i

    def ws(self):
        s, n = self.s, len(self.s)
        while self.i < n:
            c = s[self.i]
            if c in ' \t\r\n':
                self.i += 1
            elif s.startswith('--', self.i):
                if s.startswith('--[[', self.i):
                    self.i = s.index(']]', self.i) + 2
                else:
                    j = s.find('\n', self.i)
                    self.i = n if j < 0 else j + 1
            else:
                break

    def string(self):
        s = self.s
        q = s[self.i]
        if q == '[':
            m = re.match(r'\[(=*)\[', s[self.i:])
            close = ']' + m.group(1) + ']'
            start = self.i + m.end()
            end = s.index(close, start)
            self.i = end + len(close)
            return s[start:end]
        self.i += 1
        out = []
        while True:
            c = s[self.i]
            if c == q:
                self.i += 1
                return ''.join(out)
            if c == '\\':
                d = s[self.i + 1]
                if d.isdigit():
                    m = re.match(r'\d{1,3}', s[self.i + 1:])
                    out.append(chr(int(m.group(0))))
                    self.i += 1 + m.end()
                    continue
                out.append(_ESC.get(d, d))
                self.i += 2
                continue
            out.append(c)
            self.i += 1

    def value(self):
        self.ws()
        s = self.s
        c = s[self.i]
        if c == '{':
            return self.table()
        if c in '"\'' or (c == '[' and re.match(r'\[=*\[', s[self.i:])):
            return self.string()
        m = _num.match(s, self.i)
        if m and (c.isdigit() or c in '-.'):
            self.i = m.end()
            t = m.group(0)
            if t.lower().startswith(('0x', '-0x')):
                return int(t, 16)
            v = float(t)
            return int(v) if v.is_integer() and not re.search(r'[.eE]', t) else v
        m = _ident.match(s, self.i)
        if m:
            word = m.group(0)
            self.i = m.end()
            if word == 'true':
                return True
            if word == 'false':
                return False
            if word == 'nil':
                return None
            ref = word
            while True:  # a.b, a[1]
                self.ws()
                if self.i < len(s) and s[self.i] == '.':
                    m = _ident.match(s, self.i + 1)
                    ref += '.' + m.group(0)
                    self.i = m.end()
                elif self.i < len(s) and s[self.i] == '[' and not re.match(r'\[=*\[', s[self.i:]):
                    self.i += 1
                    k = self.value()
                    self.ws()
                    self.i += 1  # ]
                    ref += '[%s]' % k
                else:
                    break
            return {'ref': ref}
        raise ValueError('unexpected %r at %d' % (s[self.i:self.i + 40], self.i))

    def table(self):
        s = self.s
        self.i += 1  # {
        arr, d = [], {}
        while True:
            self.ws()
            if s[self.i] == '}':
                self.i += 1
                break
            if s[self.i] == '[' and not re.match(r'\[=*\[', s[self.i:]):
                self.i += 1
                k = self.value()
                self.ws()
                self.i += 1  # ]
                self.ws()
                self.i += 1  # =
                d[k] = self.value()
            else:
                m = _ident.match(s, self.i)
                j = m.end() if m else None
                if m and re.match(r'\s*=(?!=)', s[j:]):
                    self.i = j
                    self.ws()
                    self.i += 1
                    d[m.group(0)] = self.value()
                else:
                    arr.append(self.value())
            self.ws()
            if s[self.i] in ',;':
                self.i += 1
        if d and arr:
            for n, v in enumerate(arr, 1):
                d[n] = v
            return d
        return d if d else arr


def register_calls(src, func='Polestar.RegisterGuide'):
    """Yields the parsed table of every func({...}) call in src."""
    pos = 0
    needle = func + '('
    while True:
        i = src.find(needle, pos)
        if i < 0:
            return
        p = Parser(src, i + len(needle))
        p.ws()
        yield p.value()
        pos = p.i


def local_tables(src, name):
    """Parses `local <name> = {...}` blocks; yields each (one per guide block)."""
    for m in re.finditer(r'local %s = ' % re.escape(name), src):
        p = Parser(src, m.end())
        yield m.start(), p.value()
