// Lays every book page out with the apps' own formatter and writes the text
// elements a link may sit in: paragraph runs, Qur'an and Arabic quotation
// blocks, footnotes.  usage: node dump_blocks.mjs <book-format.js> <book_pages.json> <out.jsonl>
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
const [formatter, pagesPath, out] = process.argv.slice(2);
const {formatBookPage} = await import(pathToFileURL(formatter).href);
const pages = JSON.parse(readFileSync(pagesPath, 'utf8'));
const lines = [];
const kinds = {};
for (const page of pages) {
  const laid = formatBookPage(page);
  const els = [];
  for (const block of laid.blocks) {
    kinds[block.type] = (kinds[block.type] || 0) + 1;
    if (block.type === 'paragraph') for (const run of block.runs) els.push({k: 'run', q: !!run.quranic, t: run.text});
    else if (block.type === 'quran' || block.type === 'arabic') els.push({k: block.type, t: block.text});
  }
  for (const note of laid.footnotes || []) els.push({k: 'foot', t: note});
  lines.push(JSON.stringify({b: page.bookID, p: Number(page.page), els}));
}
writeFileSync(out, lines.join('\n') + '\n');
console.log(pages.length, 'pages', JSON.stringify(kinds));
