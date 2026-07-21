// The prefix we use for all NaN values.
const NAN_PREFIX = 0x7FF8_0000;

/**
 * Predefined references.
 * */
export const predefined = {
  "nan": 0,
  "null": 1,
  "true": 2,
  "false": 3,
  "undefined": 4,
  "globalThis": 5,
  "runtime": 6,
};
const PREDEFINED_ID_MAX = 6;

// Other globals we need
const encoder = new TextEncoder();
const decoder = new TextDecoder("utf-8");

/**
 * The main state.
 * */
export class ZigJS {
  /**
   * Set this to the memory of your WebAssembly instance prior to making
   * any Wasm calls that might interface with JS.
   *
   * We have to use a Memory object directly (rather than an ArrayBuffer)
   * so that we can always access memory even if it is resized. Otherwise,
   * a resize could detach the array buffer.
   * */
  memory?: WebAssembly.Memory;

  /**
   * The values, indexed by ID (number). Duplicate values can be in this
   * if they are loaded multiple times. That just acts as duplicate references.
   * */
  private values: Array<any> = [NaN, null, true, false, undefined, globalThis, this];

  /**
   * When a value is removed from the values array, its ID is put
   * in the pool so that we can use it next. This avoids fragmentation in
   * our array keys.
   * */
  private idPool: Array<number> = [];

  /**
   * Returns the import object that should be merged with your import
   * object when instantiating your wasm instance. This injects the required
   * functions into the wasm environment.
   * */
  importObject(): ImportObject {
    return {
      "zig-js": {
        valueGet: this.valueGet.bind(this),
        valueSet: this.valueSet.bind(this),
        valueDeinit: this.valueDeinit.bind(this),
        valueObjectCreate: this.valueObjectCreate.bind(this),
        valueStringCreate: this.valueStringCreate.bind(this),
        valueStringLen: this.valueStringLen.bind(this),
        valueStringCopy: this.valueStringCopy.bind(this),
        valueNew: this.valueNew.bind(this),
        funcApply: this.funcApply.bind(this),
      },
    };
  }

  /**
   * Get a value from the JS environment.
   * */
  protected valueGet(out: number, id: number, ptr: number, len: number): void {
    const val = this.loadValue(id);
    const str = this.loadString(ptr, len);
    const result = Reflect.get(val, str);
    this.storeValue(out, result);
  }

  /**
   * Set a value on an object.
   * */
  protected valueSet(id: number, ptr: number, len: number, refAddr: number): void {
    const obj = this.loadValue(id);
    const str = this.loadString(ptr, len);
    const val = this.loadRef(refAddr);
    Reflect.set(obj, str, val);
  }

  /**
   * Dereference a value, allowing the JS environment to potentially GC it.
   * */
  protected valueDeinit(id: number): void {
    // Do not allow deinitializing our predefined values
    if (id > PREDEFINED_ID_MAX) {
      this.values[id] = null;
      this.idPool.push(id);
    }
  }

  /**
   * Create an empty object.
   * */
  protected valueObjectCreate(out: number): void {
    this.storeValue(out, new Object());
  }

  /**
   * Creates a string on the JS side from a UTF-8 encoded string in wasm memory.
   * */
  protected valueStringCreate(out: number, ptr: number, len: number): void {
    const str = this.loadString(ptr, len);
    this.storeValue(out, str);
  }


  /**
   * Returns the length of the string given by id.
   * */
  protected valueStringLen(id: number): number {
    const val = this.loadValue(id);
    const buf = encoder.encode(val);
    return buf.byteLength;
  }

  /**
   * Copy the string at id "id" into the shared memory at ptr.
   * */
  protected valueStringCopy(id: number, ptr: number, max: number): void {
    if (this.memory == null) return;

    const dest = ptr >>> 0;
    const cap = max >>> 0;
    const val = this.loadValue(id);
    if (typeof val !== "string") return;
    const bytes = encoder.encode(val);
    if (bytes.byteLength > cap || bytes.length === 0) return;
    const buf = this.memory.buffer;
    if (dest + bytes.length > buf.byteLength) return;
    new Uint8Array(buf, dest, bytes.length).set(bytes);
  }

  /**
   * Call a constructor given by id.
   * */
  protected valueNew(out: number, id: number, argsAddr: number, argsLen: number): void {
    const fn = this.loadValue(id);
    const args = [];
    const base = argsAddr >>> 0;
    const count = argsLen >>> 0;
    for (let i = 0; i < count; i++) {
      args.push(this.loadRef(base + (i * 8)));
    }

    const result = Reflect.construct(fn, args);
    this.storeValue(out, result);
  }

  /**
   * Call a function given by id.
   * */
  protected funcApply(out: number, id: number, thisRefAddr: number, argsAddr: number, argsLen: number): void {
    const fn = this.loadValue(id);
    const thisVal = this.loadRef(thisRefAddr >>> 0);
    const args = [];
    const base = argsAddr >>> 0;
    const count = argsLen >>> 0;
    for (let i = 0; i < count; i++) {
      args.push(this.loadRef(base + (i * 8)));
    }

    const result = Reflect.apply(fn, thisVal, args);
    this.storeValue(out, result);
  }

  /**
   * This can be used to load a value given by an ID. A WASM function
   * might return a value as an ID. This can be used to retrieve it.
   * */
  loadValue(id: number): any {
    return this.values[id];
  }

  /**
   * This removes the value from the values list and returns it. This
   * will not remove predefined values but can still be used to retrieve
   * them.
   * */
  deleteValue(id: number): any {
    const val = this.values[id];
    this.valueDeinit(id);
    return val;
  }

  loadRef(refAddr: number): any {
    if (this.memory == null) return;
    const addr = refAddr >>> 0;
    const view = new DataView(this.memory.buffer);

    // If the value at the memory location is not a NaN, return it directly.
    const floatVal = view.getFloat64(addr, true);
    if (!isNaN(floatVal)) return floatVal;

    // If it is a NaN, we need to get the ID.
    const id = this.loadRefId(addr);
    return this.values[id];
  }

  loadRefId(refAddr: number): number {
    if (this.memory == null) return 0;
    return new DataView(this.memory.buffer).getUint32(refAddr >>> 0, true);
  }

  storeValue(out: number, val: any): void {
    if (this.memory == null) return;
    const view = new DataView(this.memory.buffer);
    out = out >>> 0;

    if (typeof val === "number") {
      // We have to turn NaNs into a single value (since NaN can be
      // represented by multiple encodings).
      if (isNaN(val)) {
        view.setUint32(out, predefined.nan, true);
        view.setUint32(out + 4, NAN_PREFIX, true);
      } else {
        view.setFloat64(out, val, true);
      }

      return;
    }

    if (val === null) {
      view.setUint32(out, predefined.null, true);
      view.setUint32(out + 4, NAN_PREFIX, true);
      return;
    }

    if (val === undefined) {
      view.setUint32(out, predefined.undefined, true);
      view.setUint32(out + 4, NAN_PREFIX, true);
      return;
    }

    if (typeof val === "boolean") {
      view.setUint32(out, val ? predefined.true : predefined.false, true);
      view.setUint32(out + 4, NAN_PREFIX, true);
      return;
    }

    if (typeof val === "bigint") {
      view.setFloat64(out, Number(val), true);
      return;
    }

    // Determine our ID
    let id = this.idPool.pop();
    if (id === undefined) {
      id = this.values.length;
    }
    this.values[id] = val;

    // All other values have to have a type set.
    let typeId = 0;
    switch (typeof val) {
      case "object":
        typeId = 1;
        break;
      case "string":
        typeId = 2;
        break;
      case "symbol":
        typeId = 3;
        break;
      case "function":
        typeId = 4;
        break;
    }

    // Set the fields
    view.setUint32(out, Number(id), true);
    view.setUint32(out + 4, NAN_PREFIX | typeId, true);
  }

  loadString(ptr: number, len: number): string {
    if (this.memory == null) return "";

    // WASM i32 args are signed in JS; pointers/lengths must be treated as u32.
    const start = ptr >>> 0;
    const length = Number(len) >>> 0;
    const buf = this.memory.buffer;
    if (length === 0 || start + length > buf.byteLength) return "";

    // We slice a clamped array instead of using a DataView so that
    // we can also support SharedArrayBuffers. It would probably be slightly
    // more performant (maybe?) to check and use either.
    const arr = new Uint8ClampedArray(buf, start, length);
    const data = arr.slice();
    return decoder.decode(data);
  }
}

export interface ImportObject {
  "zig-js": {
    valueGet: (out: number, id: number, ptr: number, len: number) => void;
    valueSet: (id: number, ptr: number, len: number, valueRef: number) => void;
    valueObjectCreate: (out: number) => void;
    valueStringCreate: (out: number, ptr: number, len: number) => void;
    valueStringLen: (id: number) => number;
    valueStringCopy: (id: number, ptr: number, max: number) => void;
    valueDeinit: (id: number) => void;
    valueNew: (out: number, funcId: number, argsPtr: number, argsLen: number) => void;
    funcApply: (out: number, funcId: number, thisRef: number, argsPtr: number, argsLen: number) => void;
  };
};
