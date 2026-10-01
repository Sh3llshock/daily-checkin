// Very small static file server for the front-end (no extra packages needed).
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const port = 5173;
const dir = path.dirname(fileURLToPath(import.meta.url));
const types = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".png": "image/png" };

http.createServer((req, res) => {
  const url = req.url.split("?")[0];
  const file = path.resolve(dir, "." + (url === "/" ? "/index.html" : url));
  if (!file.startsWith(dir) || !fs.existsSync(file)) {
    res.writeHead(404);
    res.end("not found");
    return;
  }
  res.writeHead(200, { "Content-Type": types[path.extname(file)] ?? "text/plain" });
  fs.createReadStream(file).pipe(res);
}).listen(port, () => {
  console.log(`Front-end running at http://localhost:${port}`);
});
