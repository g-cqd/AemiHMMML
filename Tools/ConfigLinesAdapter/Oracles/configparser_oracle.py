"""Python's configparser as an oracle for AemiConfigLines' PythonINI (Tools/ConfigLinesAdapter, ADR-0025).

Input: records of a decimal length, a line feed and that many bytes. Output, for each, one line: `OK` then, for DEFAULT and each
section in order, ` S:<name>` and its options ` O:<name>:<value>`, every field hex-encoded UTF-8; or `ERR <kind> <detail>`.
"""

import configparser
import sys


def hexed(text):
    return text.encode("utf-8").hex()


def answer(data):
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        return "ERR utf8"
    parser = configparser.RawConfigParser()
    try:
        parser.read_string(text)
    except configparser.MissingSectionHeaderError as error:
        return f"ERR missing {error.lineno}"
    except configparser.DuplicateSectionError as error:
        return f"ERR section {hexed(error.section)} {error.lineno}"
    except configparser.DuplicateOptionError as error:
        return f"ERR option {hexed(error.section)} {hexed(error.option)} {error.lineno}"
    except configparser.ParsingError as error:
        return "ERR parsing " + ",".join(str(line) for line, _ in error.errors)
    fields = ["OK", "S:" + hexed("DEFAULT")]
    fields += [f"O:{hexed(name)}:{hexed(value)}" for name, value in parser.defaults().items()]
    for section in parser.sections():
        fields.append("S:" + hexed(section))
        fields += [f"O:{hexed(name)}:{hexed(value)}" for name, value in parser._sections[section].items()]
    return " ".join(fields)


def main():
    source = sys.stdin.buffer
    while True:
        length = source.readline()
        if not length:
            return
        sys.stdout.write(answer(source.read(int(length))) + "\n")
        sys.stdout.flush()


main()
