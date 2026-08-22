const KEYWORDS = new Set([
  "module", "endmodule", "input", "output", "inout", "wire", "reg", "always",
  "assign", "begin", "end", "if", "else", "case", "endcase", "default",
  "posedge", "negedge", "parameter", "localparam", "function", "endfunction",
  "integer", "genvar", "generate", "endgenerate", "for", "while",
]);

// Tokenizes one line into { text, kind } pieces for syntax-colored spans.
// Returns React-safe data (no HTML strings) -- the caller renders each piece
// as its own <span>, so nothing here can inject markup even if the RTL text
// itself contains something that looks like HTML.
export function tokenizeLine(line) {
  const tokens = [];
  const commentIdx = line.indexOf("//");
  const code = commentIdx >= 0 ? line.slice(0, commentIdx) : line;
  const comment = commentIdx >= 0 ? line.slice(commentIdx) : "";

  const re = /(\d+'[bdhBDH][0-9a-fA-Fxz_]+|\b\d+\b|\b[a-zA-Z_]\w*\b|[^\sa-zA-Z_0-9]+|\s+)/g;
  let match;
  while ((match = re.exec(code)) !== null) {
    const word = match[0];
    let kind = "plain";
    if (/^\d+'[bdhBDH]/.test(word) || /^\d+$/.test(word)) kind = "number";
    else if (KEYWORDS.has(word)) kind = "keyword";
    tokens.push({ text: word, kind });
  }
  if (comment) tokens.push({ text: comment, kind: "comment" });
  return tokens;
}
