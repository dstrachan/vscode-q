import { readFileSync } from 'fs';
import path = require('path');

import { Position, Range } from 'vscode';

import { Token, TokenType } from './models';

let memory: WebAssembly.Memory;
let alloc_wasm: (len: number) => number;
let destroy_wasm: (ptr: number) => void;
let parse_wasm: (ptr: number, len: number) => number;

const encoder = new TextEncoder();
const decoder = new TextDecoder();

export const init = () => {
  const filePath = path.resolve(__dirname, '../../zig-out/lib/parser.wasm');
  const bytes = readFileSync(filePath);
  const module = new WebAssembly.Module(bytes);
  const instance = new WebAssembly.Instance(module, { env: { print } });
  memory = instance.exports.memory as WebAssembly.Memory;
  alloc_wasm = instance.exports.alloc as (len: number) => number;
  destroy_wasm = instance.exports.destroy as (ptr: number) => void;
  parse_wasm = instance.exports.parse as (ptr: number, len: number) => number;
};

const print = (ptr: number, len: number) => {
  const mem = new Uint8Array(memory.buffer, ptr, len);
  console.log(decoder.decode(mem));
};

const alloc = (data: Uint8Array) => {
  if (data.length === 0) return 0;
  const ptr = alloc_wasm(data.length);
  const mem = new Uint8Array(memory.buffer, ptr, data.length);
  mem.set(data);
  return ptr;
};

const parseNumber = (ptr: number) => {
  const view = new DataView(memory.buffer, ptr, 4);
  return view.getUint32(0, true);
};

const parseString = (ptr: number) => {
  const view = new DataView(memory.buffer, ptr, 8);
  const strPtr = view.getUint32(0, true);
  const len = view.getUint32(4, true);
  const mem = new Uint8Array(memory.buffer, strPtr, len);
  return decoder.decode(mem);
};

const parsePosition: (ptr: number) => Position = (ptr: number) => {
  return new Position(parseNumber(ptr), parseNumber(ptr + 4));
};

const parseRange: (ptr: number) => Range = (ptr: number) => {
  return new Range(parsePosition(ptr), parsePosition(ptr + 8));
};

const parseTokens = (ptr: number, len: number) => {
  const tokens = new Array<Token>(len);
  for (let i = 0; i < len; i++) {
    const tokenType = TokenType[parseNumber(ptr)];
    const lexeme = parseString(ptr + 4);
    const errorMessage = parseString(ptr + 12);
    const range = parseRange(ptr + 20);
    tokens[i] = {
      tokenType,
      lexeme,
      errorMessage,
      range,
    };
    ptr += 36;
  }
  return tokens;
};

const parseTokenResult = (ptr: number) => {
  const view = new DataView(memory.buffer, ptr, 8);
  const tokensPtr = view.getUint32(0, true);
  const len = view.getUint32(4, true);

  return parseTokens(tokensPtr, len);
};

export const parse = (source: string) => {
  const encodedSource = encoder.encode(source);
  const sourcePtr = alloc(encodedSource);
  const ptr = parse_wasm(sourcePtr, encodedSource.length);
  const result = parseTokenResult(ptr);
  destroy_wasm(ptr);
  return result;
};
