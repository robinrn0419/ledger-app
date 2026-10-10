// 從 www/index.html 產生可離線的網頁版，由 GitHub Actions 呼叫：node scripts/make-web.js <輸出資料夾>
// 網頁版和 App 用同一份 index.html，只多了 PWA 設定（加到主畫面的名稱和圖示）和離線快取（sw.js）。
// 快取版本號用每次打包的編號，所以不用手動加一。
const fs = require('fs');
const path = require('path');

const out = process.argv[2];
if (!out) { console.error('用法：node scripts/make-web.js <輸出資料夾>'); process.exit(1); }
const root = path.join(__dirname, '..');
const BUILD = process.env.BUILD || 'dev';
fs.mkdirSync(out, { recursive: true });

// index.html：在 <title> 後面加 PWA 設定，在 </body> 前面註冊 sw.js
let html = fs.readFileSync(path.join(root, 'www/index.html'), 'utf8');
const head = [
  '<meta name="apple-mobile-web-app-capable" content="yes">',
  '<meta name="mobile-web-app-capable" content="yes">',
  '<meta name="apple-mobile-web-app-title" content="記一筆">',
  '<meta name="apple-mobile-web-app-status-bar-style" content="default">',
  '<meta name="theme-color" content="#F2F2F7" media="(prefers-color-scheme: light)">',
  '<meta name="theme-color" content="#000000" media="(prefers-color-scheme: dark)">',
  '<link rel="apple-touch-icon" href="icon.png">',
  '<link rel="icon" type="image/png" href="icon.png">',
  '<link rel="manifest" href="manifest.webmanifest">'
].join('\n');
const sw = [
  '<script>',
  "if('serviceWorker' in navigator){",
  "  window.addEventListener('load',function(){navigator.serviceWorker.register('sw.js').catch(function(){})});",
  '}',
  '</script>'
].join('\n');
if (!html.includes('</title>') || !html.includes('</body>')) throw new Error('index.html 找不到 </title> 或 </body>');
html = html.replace('</title>', '</title>\n' + head).replace('</body>', sw + '\n</body>');
fs.writeFileSync(path.join(out, 'index.html'), html);

fs.copyFileSync(path.join(root, 'www/icon.png'), path.join(out, 'icon.png'));

fs.writeFileSync(path.join(out, 'manifest.webmanifest'), JSON.stringify({
  name: '記一筆',
  short_name: '記一筆',
  start_url: './',
  scope: './',
  display: 'standalone',
  background_color: '#F2F2F7',
  theme_color: '#F2F2F7',
  icons: [{ src: 'icon.png', sizes: '512x512', type: 'image/png', purpose: 'any' }]
}, null, 2) + '\n');

// 離線快取：有快取就先用快取，同時在背景抓新版；版本號變了就清掉舊快取
fs.writeFileSync(path.join(out, 'sw.js'), `// 記一筆：離線快取（由 scripts/make-web.js 產生，版本號是打包編號）
var VERSION = 'ledger-${BUILD}';
var CORE = ['./', 'index.html', 'icon.png', 'manifest.webmanifest'];

self.addEventListener('install', function (e) {
  e.waitUntil(caches.open(VERSION).then(function (c) { return c.addAll(CORE); }).then(function () { return self.skipWaiting(); }));
});

self.addEventListener('activate', function (e) {
  e.waitUntil(
    caches.keys().then(function (keys) {
      return Promise.all(keys.filter(function (k) { return k !== VERSION; }).map(function (k) { return caches.delete(k); }));
    }).then(function () { return self.clients.claim(); })
  );
});

self.addEventListener('fetch', function (e) {
  if (e.request.method !== 'GET') return;
  e.respondWith(
    caches.open(VERSION).then(function (cache) {
      return cache.match(e.request, { ignoreSearch: e.request.mode === 'navigate' }).then(function (hit) {
        var fresh = fetch(e.request).then(function (res) {
          if (res && (res.ok || res.type === 'opaque')) cache.put(e.request, res.clone());
          return res;
        }).catch(function () { return hit || (e.request.mode === 'navigate' ? cache.match('index.html') : undefined); });
        return hit || fresh;
      });
    })
  );
});
`);

console.log('網頁版已產生到 ' + out + '（快取版本 ledger-' + BUILD + '）');
