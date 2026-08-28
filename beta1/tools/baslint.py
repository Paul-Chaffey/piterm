#!/usr/bin/env python3
"""Check BBC BASIC sources for the mistakes that cost a trip to the machine.

    tools/baslint.py src/fbvdu.bas test/*.bas

BBC BASIC reports almost nothing until the offending line executes, so a
misspelled PROC in an error handler or a missing NEXT in a rarely-taken
branch surfaces on the hardware, minutes into a run. These are the checks
that can be made from here:

  - a PROC or FN called but never defined (and the reverse, which is
    usually dead code rather than a fault)
  - FOR/NEXT and REPEAT/UNTIL unbalanced within a procedure
  - DEF PROC without ENDPROC on the path out
  - lines too long for the 238-byte input buffer that *EXEC types through
  - BASIC V keywords in a file that is meant to stay BASIC IV safe

It parses text, not tokens, so it is a lint and not a compiler: it will not
catch a syntax error inside a line.
"""
import re, sys

BASIC5 = re.compile(r'\b(CASE|WHILE|ENDWHILE|ENDCASE|REPORT\$|WHEN|OTHERWISE|SYS|INSTALL|LIBRARY)\b')
# BASIC V's local error handling. Two words each, so the single-keyword
# list above cannot see them: LOCAL, ON ERROR and RESTORE are all legal
# BASIC IV on their own. Cost a rewrite of test/fbboot.bas on 2026-08-21,
# which baslint had passed clean.
BASIC5_PAIR = re.compile(r'\b(LOCAL\s+ERROR|ON\s+ERROR\s+LOCAL|RESTORE\s+ERROR)\b')


def strip(line):
    """Drop the line number, comments and string literals."""
    code = re.sub(r'^\s*\d+\s?', '', line.rstrip('\n'))
    code = re.sub(r'"[^"]*"', '""', code)
    code = re.sub(r'\bREM\b.*$', '', code)
    return code


# Pseudo-variables and things BASIC supplies. Reading one of these without
# assigning it is correct, so they must not be reported.
BUILTIN = {
    'TIME', 'PAGE', 'TOP', 'LOMEM', 'HIMEM', 'COUNT', 'ERR', 'ERL', 'POS',
    'VPOS', 'WIDTH', 'PTR', 'EXT', 'TRUE', 'FALSE', 'PI', 'RND', 'ADVAL',
    'INKEY', 'GET', 'EOF', 'OPENIN', 'OPENOUT', 'OPENUP', 'BGET', 'INSTR',
    'ASC', 'LEN', 'VAL', 'STR', 'CHR', 'MID', 'LEFT', 'RIGHT', 'STRING',
    'ABS', 'INT', 'SGN', 'SQR', 'SIN', 'COS', 'TAN', 'LOG', 'EXP', 'DEG',
    'RAD', 'USR', 'EVAL', 'MODE', 'DIM', 'END', 'ENDPROC', 'THEN', 'ELSE',
}

# A name READ BEFORE IT IS ASSIGNED. On most BASICs that is a zero and a
# subtle wrong answer; on BBC BASIC it is "No such variable" and the program
# STOPS - which on a co-processor, mid-handshake, is indistinguishable from a
# hang. An uninitialised heartbeat timer cost two hardware runs on 2026-08-28:
#
#   1500 IF (TIME-tp%)>500 THEN PROCprog:tp%=TIME
#
# tp% is assigned on that very line, so asking "is it ever assigned" sees
# nothing wrong. What is wrong is the ORDER, and only in the main body is
# textual order the same as execution order - inside a PROC it is not, because
# the PROC may be called from anywhere. So the check runs over the main body
# only, statement by statement, and stops at the first DEF.
SIMPLE_ASSIGN = re.compile(r'(?:^|:)\s*([A-Za-z_][A-Za-z_0-9]*[%$]?)\s*=')
FORVAR = re.compile(r'\bFOR\s+([A-Za-z_][A-Za-z_0-9]*[%$]?)\s*=')
LOCALS = re.compile(r'\b(?:LOCAL|DIM)\s+([^:]*)')
DEFARGS = re.compile(r'\bDEF\s*(?:PROC|FN)\w*\s*\(([^)]*)\)')
NAMES = re.compile(r'\b([A-Za-z_][A-Za-z_0-9]*[%$]?)')
THEN_ASSIGN = r'\bTHEN\s+([A-Za-z_][A-Za-z_0-9]*[%$]?)\s*='


def check(path, basic4=False):
    defs, calls, faults = set(), {}, []
    assigned, referenced = set(), {}
    body_seen, body_faults, in_body = set(), {}, True
    proc_assigned = set()
    # A duplicate line number is only ever a mistake, and in a combined
    # build it is a SILENT one: the engine holds 1000-9990 and a driver
    # 10-990 plus 10000 up, so a driver numbered from 1000 interleaves
    # with the engine and the machine runs whichever line it reaches.
    # That is what "Error 26 at line 1390" turned out to be - fbscroll's
    # PROCerr sitting on top of the engine's fastblank%=TRUE.
    seen_lines = {}
    # RESTORE names a line, but BASIC reads from the first DATA AT OR AFTER
    # it, so a RESTORE that does not name a DATA line works by accident: it
    # depends on nothing else defining DATA in the gap. src/fbvdu.bas had one
    # reaching 238 lines forward for the font table.
    data_lines, restores = set(), []
    proc, counts = "(top level)", {}
    ends = {}
    for n, raw in enumerate(open(path), 1):
        code = strip(raw)
        if len(raw.rstrip('\n')) > 238:
            faults.append(f"{path}:{n}: line is {len(raw.rstrip())} chars, over the 238-byte input buffer")
        ln = re.match(r'\s*(\d+)', raw)
        if ln:
            num = int(ln.group(1))
            if num in seen_lines:
                faults.append(f"{path}:{n}: line {num} appears twice "
                              f"(first at input line {seen_lines[num]})")
            seen_lines[num] = n
            if any(s.lstrip().startswith('DATA') for s in code.split(':')):
                data_lines.add(num)
        for m2 in re.finditer(r'\bRESTORE\s+(\d+)', code):
            restores.append((n, int(m2.group(1))))
        # The main body ends at the first DEF; after that, textual order says
        # nothing about when a line runs.
        if in_body and re.match(r'\s*DEF\s+(PROC|FN)', code):
            in_body = False
        if in_body:
            for stmt in code.split(':'):
                # Names BOUND BY this statement, registered before its reads
                # are judged. FOR's control variable and DIM's targets are
                # assignments even though neither uses a plain '='; scanning
                # reads first reported both as uninitialised.
                for m2 in FORVAR.finditer(stmt):
                    body_seen.add(m2.group(1))
                # INPUT and READ assign too, and INPUT's prompt has already
                # been blanked by strip(), so what is left is the variables.
                im = re.search(r'\b(?:INPUT|READ)\b(.*)', stmt)
                if im:
                    for m2 in re.finditer(r'[A-Za-z_][A-Za-z_0-9]*[%$]?', im.group(1)):
                        body_seen.add(m2.group(0))
                # SYS's TO clause names OUTPUT variables: SYS "OS_Byte",... TO ,a%
                sm = re.search(r'\bSYS\b.*?\bTO\b(.*)', stmt)
                if sm:
                    for m2 in re.finditer(r'[A-Za-z_][A-Za-z_0-9]*[%$]?', sm.group(1)):
                        body_seen.add(m2.group(0))
                dm = re.search(r'\bDIM\s+(.*)', stmt)
                if dm:
                    # Only the name after DIM or after a comma is a target.
                    # The size beside it may be a variable, and that is a READ:
                    # DIM buf% siz% must not mark siz% as assigned.
                    for m2 in re.finditer(r'(?:^|,)\s*([A-Za-z_][A-Za-z_0-9]*[%$]?)',
                                          dm.group(1)):
                        body_seen.add(m2.group(1))
                # An assignment can hide after THEN: IF c%=0 THEN e%=TIME.
                # Its target is bound by this statement, so a later statement
                # reading e% is fine - but the target must not be counted as a
                # read of itself while scanning this one.
                then_t = re.findall(THEN_ASSIGN, stmt)
                stmt_r = re.sub(THEN_ASSIGN, 'THEN ', stmt)
                asn = SIMPLE_ASSIGN.match(':' + stmt_r)
                target = asn.group(1) if asn else None
                # The right-hand side is read BEFORE the target is bound, so
                # x%=x%+1 with no prior x% is still a fault.
                scan = stmt_r[asn.end() - 1:] if asn else stmt_r
                for m2 in NAMES.finditer(scan):
                    nm = m2.group(1)
                    if nm.isupper() and not nm.endswith(('%', '$')):
                        continue
                    if nm in BUILTIN or nm.rstrip('%$') in BUILTIN:
                        continue
                    if nm not in body_seen:
                        body_faults.setdefault(nm, n)
                if target:
                    body_seen.add(target)
                for nm in then_t:
                    body_seen.add(nm)
                for m2 in re.finditer(r'\b([A-Za-z_][A-Za-z_0-9]*[%$]?)\s*[?!][^=]*=', stmt):
                    body_seen.add(m2.group(1))

        if not in_body:
            for stmt in code.split(':'):
                a3 = SIMPLE_ASSIGN.match(':' + stmt)
                if a3:
                    proc_assigned.add(a3.group(1))
                for nm in re.findall(THEN_ASSIGN, stmt):
                    proc_assigned.add(nm)
                s3 = re.search(r'\bSYS\b.*?\bTO\b(.*)', stmt)
                if s3:
                    for m3 in re.finditer(r'[A-Za-z_][A-Za-z_0-9]*[%$]?', s3.group(1)):
                        proc_assigned.add(m3.group(0))
                for m3 in FORVAR.finditer(stmt):
                    proc_assigned.add(m3.group(1))
                i3 = re.search(r'\b(?:INPUT|READ)\b(.*)', stmt)
                if i3:
                    for m3 in re.finditer(r'[A-Za-z_][A-Za-z_0-9]*[%$]?', i3.group(1)):
                        proc_assigned.add(m3.group(0))
                d3 = re.search(r'\bDIM\s+(.*)', stmt)
                if d3:
                    for m3 in re.finditer(r'(?:^|,)\s*([A-Za-z_][A-Za-z_0-9]*[%$]?)',
                                          d3.group(1)):
                        proc_assigned.add(m3.group(1))

        m = re.match(r'\s*DEF\s+(PROC|FN)(\w+)', code)
        if m:
            proc = m.group(1) + m.group(2)
            defs.add(proc)
            counts[proc] = {'FOR': 0, 'NEXT': 0, 'REPEAT': 0, 'UNTIL': 0}
            ends[proc] = False
        for kind, name in re.findall(r'\b(PROC|FN)(\w+)', re.sub(r'\bDEF\s+(PROC|FN)\w+', '', code)):
            calls.setdefault(kind + name, []).append(n)
        # Collect assignments and references for the read-before-write check.
        for part in code.split(':'):
            m2 = SIMPLE_ASSIGN.match(':' + part)
            if m2:
                assigned.add(m2.group(1))
        for m2 in FORVAR.finditer(code):
            assigned.add(m2.group(1))
        for m2 in LOCALS.finditer(code):
            for nm in re.findall(r'[A-Za-z_][A-Za-z_0-9]*[%$]?', m2.group(1)):
                assigned.add(nm)
        for m2 in DEFARGS.finditer(code):
            for nm in re.findall(r'[A-Za-z_][A-Za-z_0-9]*[%$]?', m2.group(1)):
                assigned.add(nm)
        # Indirection targets (a%?0=, a%!4=) assign through a pointer, so the
        # pointer itself is a read, but the statement is still an assignment.
        for m2 in re.finditer(r'\b([A-Za-z_][A-Za-z_0-9]*[%$]?)\s*[?!]', code):
            referenced.setdefault(m2.group(1), []).append(n)
        for m2 in NAMES.finditer(re.sub(r'\bDEF\s*(?:PROC|FN)\w*', '', code)):
            nm = m2.group(1)
            if nm.isupper() and not nm.endswith(('%', '$')):
                continue        # a keyword, not a variable
            referenced.setdefault(nm, []).append(n)

        c = counts.setdefault(proc, {'FOR': 0, 'NEXT': 0, 'REPEAT': 0, 'UNTIL': 0})
        for kw in ('FOR', 'NEXT', 'REPEAT', 'UNTIL'):
            c[kw] += len(re.findall(r'\b' + kw + r'\b', code))
        # END is a legitimate way out of a procedure that stops the program,
        # so it counts as an exit and is not a missing ENDPROC.
        if proc.startswith('PROC') and re.search(r'\bENDPROC\b|\bEND\b', code):
            ends[proc] = True
        if proc.startswith('FN') and re.search(r'^\s*=', code):
            ends[proc] = True
        # The single-line form, DEF FNh(n%)="&"+STR$~n%, returns on the DEF
        # line itself and has no leading = anywhere. It is ordinary BBC
        # BASIC and test/nettest.bas has used it since the first probe, so
        # the rule above reported a fault on code that has run on hardware -
        # and a linter that cries wolf is one people stop reading.
        if re.match(r'\s*DEF\s+FN\w*(\([^)]*\))?\s*=', code):
            ends[proc] = True
        # A $ in an FN or PROC name is found by the DEF search and then
        # raises "No such variable" when the function is entered, on both
        # BASIC 2 and BASIC 4. The return type comes from the = expression,
        # so the $ carries no meaning and costs an afternoon.
        if re.match(r'\s*DEF\s+(PROC|FN)\w*\$', code):
            faults.append(f"{path}:{n}: a $ in an FN or PROC name raises No such variable when called - drop it")
        # A * COMMAND TAKES THE WHOLE REST OF ITS LINE. Two of them separated
        # by a colon is one command with the second as trailing argument text:
        # *FX202,48:*FX118 sets the keyboard byte and never updates the LEDs,
        # and *FX118 is silently not a command at all. Cost a hardware run on
        # 2026-08-28, where the symptom was caps lock still being on.
        star = re.match(r'\s*(?:\w+\s*=\s*)?\*', code)
        if star and ':' in code[code.index('*'):]:
            faults.append(f"{path}:{n}: a * command takes the rest of the line - "
                          f"the part after the colon is not a command")
        # ELSE binds to the FIRST IF on the line, not the nearest, so a
        # nested IF ... THEN IF ... ELSE runs the ELSE when the OUTER test
        # fails. It is never what was meant.
        if re.search(r'\bIF\b.*\bTHEN\b.*\bIF\b.*\bELSE\b', code):
            faults.append(f"{path}:{n}: nested IF with ELSE - ELSE binds to the first IF on the line")
        if basic4:
            b5 = BASIC5.search(code) or BASIC5_PAIR.search(code)
            if b5:
                faults.append(f"{path}:{n}: {b5.group(1)} is BASIC V only")
    # Out of order line numbers. BASIC stores a program as an ascending
    # chain and LIST, RENUMBER and *EXEC all assume it; a file built out
    # of order is malformed rather than merely untidy. Two insertions on
    # 2026-08-22 landed out of order and only a duplicate check caught the
    # first of them.
    nums = list(seen_lines)
    for a, b in zip(nums, nums[1:]):
        if a >= b:
            faults.append(f"{path}: line {b} is written after line {a} - "
                          f"line numbers must ascend")
            break

    for name, lines in sorted(calls.items()):
        if name not in defs:
            faults.append(f"{path}:{lines[0]}: {name} called but never defined")
    for name in sorted(defs - set(calls)):
        faults.append(f"{path}: {name} defined but never called")
    for name, c in counts.items():
        if c['FOR'] != c['NEXT']:
            faults.append(f"{path}: {name} has {c['FOR']} FOR and {c['NEXT']} NEXT")
        if c['REPEAT'] != c['UNTIL']:
            faults.append(f"{path}: {name} has {c['REPEAT']} REPEAT and {c['UNTIL']} UNTIL")
    # A name a PROCEDURE assigns is not reported, even when the body reads it
    # first textually: the body may well have called that procedure by then,
    # and this lint cannot know. That silences the whole vfail$ / handler
    # class, which is real working code, and leaves the case that actually
    # bites - a name whose only assignment is later in the straight-line body.
    # ONLY FOR A SELF-CONTAINED PROGRAM. Several files here are drivers that
    # run on top of src/fbvdu.bas, and their engine variables - vfail$, fb%,
    # pit%, fastmv% - are assigned in that other file. A file that calls a
    # PROC it does not define is such a fragment, and this check has nothing
    # useful to say about it.
    fragment = any(name not in defs for name in calls)
    for name, line in sorted(body_faults.items(), key=lambda kv: kv[1]):
        if fragment:
            break
        if name in defs or name.startswith(('PROC', 'FN')):
            continue
        if name in proc_assigned:
            continue
        faults.append(f"{path}:{line}: {name} is read before it is assigned - "
                      f"BBC BASIC stops with No such variable")

    for n, tgt in restores:
        if tgt not in seen_lines:
            faults.append(f"{path}:{n}: RESTORE {tgt} names a line that does not exist")
        elif tgt not in data_lines:
            faults.append(f"{path}:{n}: RESTORE {tgt} does not name a DATA line - "
                          f"it reads from the next DATA in the file, wherever that ends up")

    for name, ok in ends.items():
        if not ok:
            faults.append(f"{path}: {name} has no ENDPROC or = on any line")
    return faults


def main():
    args = sys.argv[1:]
    basic4 = "--basic4" in args
    paths = [a for a in args if not a.startswith("--")]
    bad = 0
    for p in paths:
        for f in check(p, basic4):
            print(f)
            bad += 1
    print(f"{len(paths)} file(s), {bad} finding(s)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
