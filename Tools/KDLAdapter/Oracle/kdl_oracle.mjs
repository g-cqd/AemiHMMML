// @bgotink/kdl (KDL 2.0) as an oracle for AemiHMMML's AemiKDL (Tools/KDLAdapter, ADR-0026).
//
// Input: records of a decimal length, a line feed and that many bytes. Output, one line each: `ERR`, or `OK` and the document as
// tokens: per node, depth first, `N<depth>:<type>:<name>`, then `A:<type>:<value>` per argument, then `P:<name>:<type>:<value>`
// per property (each name once, its rightmost value, sorted by name). Strings and types are hex UTF-8 (`-` for no type); values
// are `S<hex>`, `I<decimal>` for an integer (exact, from the number as written, by JavaScript's BigInt), `F<f64 bits in hex>`,
// `NAN`, `B1`, `B0` or `Z`.
import {readFileSync, writeFileSync} from "node:fs";
import {createRequire} from "node:module";

// @bgotink/kdl 0.4.1 counts `:;<=>?` as hexadecimal digits: its `isHexadecimalDigit` tests `codePoint < 0x40` where it means
// `< 0x3a`, so `node 0xff;x` fails and `node 0x1=` reads. That one comparison is corrected in the installed copy before the
// parser loads (ADR-0026); anything else about the file, and the oracle refuses to run.
const types = createRequire(import.meta.url).resolve("@bgotink/kdl/package.json").replace(/package\.json$/, "parser/tokenize/types.js");
const buggy = "(codePoint >= 0x30 && codePoint < 0x40) || // decimal";
const fixed = "(codePoint >= 0x30 && codePoint < 0x3a) || // decimal";
const source = readFileSync(types, "utf8");
if (source.includes(buggy)) writeFileSync(types, source.replace(buggy, fixed));
else if (!source.includes(fixed)) throw new Error(`${types} is not the file this oracle corrects`);
const {parse} = await import("@bgotink/kdl");

const utf8 = new TextDecoder("utf-8", {fatal: true, ignoreBOM: true});
const hex = (text) => Buffer.from(text, "utf8").toString("hex");
const type = (tag) => (tag === null || tag === undefined ? "-" : hex(tag));

function float(number) {
  const view = new DataView(new ArrayBuffer(8));
  view.setFloat64(0, number);
  return view.getBigUint64(0).toString(16);
}

// KDL's number grammar; group 2 is set when the number has a fraction or an exponent.
const number = /^([+-]?(?:0x[0-9a-f][0-9a-f_]*|0o[0-7][0-7_]*|0b[01][01_]*|[0-9][0-9_]*((?:\.[0-9][0-9_]*)?(?:e[+-]?[0-9][0-9_]*)|\.[0-9][0-9_]*)?))/i;

function value(entry) {
  const v = entry.getValue();
  if (typeof v === "string") return "S" + hex(v);
  if (typeof v === "boolean") return v ? "B1" : "B0";
  if (v === null) return "Z";
  if (Number.isNaN(v)) return "NAN";
  // The number as written (the representation can run past it, to a following `;`), when it is an integer.
  const written = number.exec(entry.value.representation ?? "");
  if (written && written[2] === undefined) {
    const negative = written[1].startsWith("-");
    const digits = written[1].replace(/^[+-]/, "").replaceAll("_", "").toLowerCase();
    const exact = BigInt(digits);
    return "I" + (negative && exact !== 0n ? "-" : "") + exact.toString();
  }
  return "F" + float(v);
}

function walk(document, depth, out) {
  for (const node of document.nodes) {
    out.push(`N${depth}:${type(node.getTag())}:${hex(node.getName())}`);
    for (const entry of node.getArgumentEntries()) out.push(`A:${type(entry.getTag())}:${value(entry)}`);
    const properties = [...node.getPropertyEntryMap().entries()];
    properties.sort((a, b) => Buffer.compare(Buffer.from(a[0], "utf8"), Buffer.from(b[0], "utf8")));
    for (const [name, entry] of properties) out.push(`P:${hex(name)}:${type(entry.getTag())}:${value(entry)}`);
    if (node.children) walk(node.children, depth + 1, out);
  }
}

function answer(bytes) {
  let text;
  try {
    text = utf8.decode(bytes);
  } catch {
    return "ERR";
  }
  let document;
  try {
    document = parse(text);
  } catch {
    return "ERR";
  }
  const tokens = ["OK"];
  walk(document, 0, tokens);
  return tokens.join(" ");
}

let pending = Buffer.alloc(0);
process.stdin.on("data", (chunk) => {
  pending = Buffer.concat([pending, chunk]);
  while (true) {
    const newline = pending.indexOf(10);
    if (newline < 0) return;
    const length = Number(pending.subarray(0, newline).toString());
    if (pending.length < newline + 1 + length) return;
    const record = pending.subarray(newline + 1, newline + 1 + length);
    pending = pending.subarray(newline + 1 + length);
    process.stdout.write(answer(record) + "\n");
  }
});
