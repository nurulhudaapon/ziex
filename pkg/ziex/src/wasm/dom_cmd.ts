/**
 * DomCmd flush decoder — must match `src/runtime/client/dom_cmd.zig`.
 *
 * Buffer layout (little-endian):
 *   Header (8): u32 record_count, u32 flags (0 = absolute WASM ptr+len strings)
 *   Records (24 each): u8 op, u8 flags, u16 pad, u32 p0..p4
 *
 * String fields are absolute linear-memory pointers (same as the old per-op ABI).
 */

import { getMemoryView, readString, loadValueFromRef } from "./core";
import { TAG_NAMES } from "./generated/tags";
import { SVG_TAG_START_INDEX, CUSTOM_TAG_INDEX } from "./generated/tag_indices";
import {
    DOM_CMD_HEADER_SIZE,
    DOM_CMD_RECORD_SIZE,
    DomOp_CreateElement,
    DomOp_CreateText,
    DomOp_HydrateInsert,
    DomOp_SetAttr,
    DomOp_SetProp,
    DomOp_RemoveAttr,
    DomOp_SetNodeValue,
    DomOp_SetInnerHtml,
    DomOp_AppendChild,
    DomOp_InsertBefore,
    DomOp_RemoveChild,
    DomOp_ReplaceChild,
} from "./constants";

export type DomFlushContext = {
    domNodes: Map<number, Node>;
    cleanupDomNodes: (node: Node) => void;
};

/** Apply a DomCmd buffer written at `ptr` with byte length `len`. */
export function flushDomCmds(ptr: number, len: number, ctx: DomFlushContext): void {
    const start = ptr >>> 0;
    const length = len >>> 0;
    if (length < DOM_CMD_HEADER_SIZE) return;

    const mem = getMemoryView();
    if (start + length > mem.byteLength) return;

    // Read records via a DataView over the command region only.
    const view = new DataView(mem.buffer, mem.byteOffset + start, length);
    const count = view.getUint32(0, true);
    const recordsBytes = count * DOM_CMD_RECORD_SIZE;
    if (DOM_CMD_HEADER_SIZE + recordsBytes > length) return;

    const { domNodes, cleanupDomNodes } = ctx;

    for (let i = 0; i < count; i++) {
        const off = DOM_CMD_HEADER_SIZE + i * DOM_CMD_RECORD_SIZE;
        const op = view.getUint8(off);
        const p0 = view.getUint32(off + 4, true);
        const p1 = view.getUint32(off + 8, true);
        const p2 = view.getUint32(off + 12, true);
        const p3 = view.getUint32(off + 16, true);
        const p4 = view.getUint32(off + 20, true);

        switch (op) {
            case DomOp_CreateElement: {
                const isCustom = p0 === CUSTOM_TAG_INDEX;
                const tagName = isCustom ? readString(p2, p3) : TAG_NAMES[p0]!;
                const el = !isCustom && p0 >= SVG_TAG_START_INDEX
                    ? document.createElementNS("http://www.w3.org/2000/svg", tagName)
                    : document.createElement(tagName);
                (el as any).__zx_ref = p1;
                domNodes.set(p1, el);
                break;
            }
            case DomOp_CreateText: {
                const node = document.createTextNode(readString(p0, p1));
                (node as any).__zx_ref = p2;
                domNodes.set(p2, node);
                break;
            }
            case DomOp_HydrateInsert: {
                const child = domNodes.get(p0);
                const ref = BigInt(p1) | (BigInt(p2) << 32n);
                const end = loadValueFromRef(ref) as ChildNode | null | undefined;
                if (!child || !end?.parentNode) break;
                end.parentNode.insertBefore(child, end);
                break;
            }
            case DomOp_SetAttr: {
                (domNodes.get(p0) as Element | undefined)
                    ?.setAttribute(readString(p1, p2), readString(p3, p4));
                break;
            }
            case DomOp_SetProp: {
                const el = domNodes.get(p0) as any;
                if (el) {
                    const name = readString(p1, p2);
                    const val = readString(p3, p4);
                    if (name === "checked" || name === "selected" || name === "muted") {
                        el[name] = val !== "false";
                    } else {
                        el[name] = val;
                    }
                }
                break;
            }
            case DomOp_RemoveAttr: {
                (domNodes.get(p0) as Element | undefined)
                    ?.removeAttribute(readString(p1, p2));
                break;
            }
            case DomOp_SetNodeValue: {
                const node = domNodes.get(p0);
                if (node) node.nodeValue = readString(p1, p2);
                break;
            }
            case DomOp_SetInnerHtml: {
                const el = domNodes.get(p0) as Element | undefined;
                if (el) el.innerHTML = readString(p1, p2);
                break;
            }
            case DomOp_AppendChild: {
                const parent = domNodes.get(p0);
                const child = domNodes.get(p1);
                if (parent && child) parent.appendChild(child);
                break;
            }
            case DomOp_InsertBefore: {
                const parent = domNodes.get(p0);
                const child = domNodes.get(p1);
                const refNode = domNodes.get(p2) ?? null;
                if (parent && child) parent.insertBefore(child, refNode);
                break;
            }
            case DomOp_RemoveChild: {
                const parent = domNodes.get(p0);
                const child = domNodes.get(p1);
                if (parent && child) {
                    parent.removeChild(child);
                    cleanupDomNodes(child);
                }
                break;
            }
            case DomOp_ReplaceChild: {
                const parent = domNodes.get(p0);
                const newChild = domNodes.get(p1);
                const oldChild = domNodes.get(p2);
                if (parent && newChild && oldChild) {
                    parent.replaceChild(newChild, oldChild);
                    cleanupDomNodes(oldChild);
                }
                break;
            }
            default:
                break;
        }
    }
}
