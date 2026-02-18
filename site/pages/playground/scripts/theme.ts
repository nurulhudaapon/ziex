import { EditorView } from "@codemirror/view";
import { HighlightStyle, syntaxHighlighting } from "@codemirror/language";
import { tags as t } from "@lezer/highlight";

export const editorTheme = EditorView.theme(
  {
    "&": {
      backgroundColor: "transparent",
      color: "#eeffff",
      fontSize: "0.82rem",
      fontFamily: "'Monaco', 'Menlo', 'Ubuntu Mono', 'Consolas', monospace",
    },
    ".cm-content": {
      caretColor: "#00d9ff",
      padding: "0.5rem 0",
    },
    ".cm-cursor, .cm-dropCursor": {
      borderLeftColor: "#00d9ff",
    },
    "&.cm-focused .cm-selectionBackground, .cm-selectionBackground, .cm-content ::selection": {
      backgroundColor: "rgba(0, 217, 255, 0.15)",
    },
    ".cm-activeLine": {
      backgroundColor: "rgba(255, 255, 255, 0.03)",
    },
    "&.cm-focused .cm-matchingBracket": {
      backgroundColor: "rgba(255, 255, 255, 0.12)",
      outline: "1px solid rgba(255, 255, 255, 0.2)",
    },
    /* Line number gutter styling */
    ".cm-gutters": {
      backgroundColor: "transparent",
      color: "rgba(255, 255, 255, 0.18)",
      borderRight: "1px solid rgba(255, 255, 255, 0.06)",
      fontVariantNumeric: "tabular-nums",
    },
    ".cm-gutter": {
      backgroundColor: "transparent",
    },
    ".cm-gutterElement": {
      backgroundColor: "transparent",
      color: "rgba(255, 255, 255, 0.18)",
      paddingLeft: "0.75rem",
      paddingRight: "1rem",
    },
    ".cm-activeLineGutter": {
      backgroundColor: "transparent",
      color: "rgba(255, 255, 255, 0.45)",
    },
    /* Tooltip styling */
    ".cm-tooltip": {
      backgroundColor: "#111111",
      color: "#eeffff",
      border: "1px solid #262626",
      borderRadius: "6px",
      boxShadow: "0 8px 32px rgba(0, 0, 0, 0.5)",
    },
    ".cm-tooltip.cm-tooltip-autocomplete": {
      backgroundColor: "#111111",
      border: "1px solid #262626",
    },
    ".cm-tooltip-autocomplete ul li[aria-selected]": {
      backgroundColor: "rgba(0, 217, 255, 0.12)",
      color: "#eeffff",
    },
    /* Scrollbar styling */
    ".cm-scroller": {
      scrollbarWidth: "thin" as any,
      scrollbarColor: "rgba(255, 255, 255, 0.14) transparent",
    },
  },
  {}
);

/* Syntax highlighting matching playground.css / home.css color palette */
export const editorHighlightStyle = syntaxHighlighting(
  HighlightStyle.define([
    { tag: t.comment, color: "#7a9aa8", fontStyle: "italic" },
    { tag: t.lineComment, color: "#7a9aa8", fontStyle: "italic" },
    { tag: t.blockComment, color: "#7a9aa8", fontStyle: "italic" },

    { tag: t.keyword, color: "#c792ea" },
    { tag: t.controlKeyword, color: "#c792ea" },
    { tag: t.operatorKeyword, color: "#89ddff" },
    { tag: t.definitionKeyword, color: "#c792ea" },
    { tag: t.moduleKeyword, color: "#c792ea" },

    { tag: t.operator, color: "#89ddff" },
    { tag: t.punctuation, color: "#89ddff" },
    { tag: t.bracket, color: "#89ddff" },
    { tag: t.separator, color: "#89ddff" },

    { tag: t.string, color: "#c3e88d" },
    { tag: t.special(t.string), color: "#c3e88d" },
    { tag: t.escape, color: "#eeffff" },

    { tag: t.number, color: "#f78c6c" },
    { tag: t.integer, color: "#f78c6c" },
    { tag: t.float, color: "#f78c6c" },
    { tag: t.bool, color: "#f78c6c" },

    { tag: t.function(t.variableName), color: "#82aaff" },
    { tag: t.function(t.definition(t.variableName)), color: "#82aaff" },

    { tag: t.typeName, color: "#ffcb6b" },
    { tag: t.className, color: "#ffcb6b" },
    { tag: t.definition(t.typeName), color: "#ffcb6b" },

    { tag: t.variableName, color: "#eeffff" },
    { tag: t.definition(t.variableName), color: "#eeffff" },
    { tag: t.special(t.variableName), color: "#82aaff" },
    { tag: t.propertyName, color: "#f78c6c" },

    { tag: t.attributeName, color: "#f78c6c" },
    { tag: t.labelName, color: "#c792ea" },

    { tag: t.tagName, color: "#f07178" },
    { tag: t.meta, color: "#89ddff" },
  ])
);
