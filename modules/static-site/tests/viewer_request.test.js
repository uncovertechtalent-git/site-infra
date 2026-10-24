// Behaviour test for the viewer-request function: renders the template with a
// sample table (the machinebehavior.io map) and checks the redirects and the
// pass-through paths. Run: node modules/static-site/tests/viewer_request.test.js
'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');

const PATH_REDIRECTS = {
  '/continuous-conformity/': '/conformity/standard/',
  '/continuous-conformity-self-assessment/': '/conformity/self-assessment/',
  '/claims/': '/research/claims/',
  '/experiments/': '/research/experiments/',
  '/slips/': '/research/slips/',
  '/terms/': '/research/terms/',
  '/red-team/': '/research/red-team/',
  '/the-cheating-moved/': '/research/articles/the-cheating-moved/'
};

const template = fs.readFileSync(path.join(__dirname, '..', 'functions', 'viewer-request.js.tftpl'), 'utf8');
const code = template
  .replace('${jsonencode(canonical_host)}', JSON.stringify('example.org'))
  .replace('${jsonencode(redirect_hosts)}', JSON.stringify(['www.example.org']))
  .replace('${jsonencode(path_redirects)}', JSON.stringify(PATH_REDIRECTS));
const handler = new Function(code + '\nreturn handler;')();

function run(uri, host, querystring) {
  const r = handler({ request: { uri: uri, headers: { host: { value: host || 'example.org' } }, querystring: querystring || {} } });
  return r.statusCode ? '301 ' + r.headers.location.value : 'pass ' + r.uri;
}

const cases = [
  ['/claims/', '301 https://example.org/research/claims/'],
  ['/claims', '301 https://example.org/research/claims/'],
  ['/experiments/stance/labels.csv', '301 https://example.org/research/experiments/stance/labels.csv'],
  ['/slips/log.csv', '301 https://example.org/research/slips/log.csv'],
  ['/continuous-conformity/why/', '301 https://example.org/conformity/standard/why/'],
  ['/continuous-conformity-self-assessment/second-rater/a.json', '301 https://example.org/conformity/self-assessment/second-rater/a.json'],
  ['/the-cheating-moved/', '301 https://example.org/research/articles/the-cheating-moved/'],
  ['/research/red-team/', 'pass /research/red-team/index.html'],
  ['/cto-powersuit/red-team/', 'pass /cto-powersuit/red-team/index.html'],
  ['/terms-of-use/', 'pass /terms-of-use/index.html'],
  ['/about', '301 https://example.org/about/']
];
for (const [uri, want] of cases) assert.strictEqual(run(uri), want, uri);

assert.strictEqual(run('/claims/', 'example.org', { a: { value: '1' } }), '301 https://example.org/research/claims/?a=1', 'query kept');
assert.strictEqual(run('/claims/', 'next.example.org'), '301 https://next.example.org/research/claims/', 'test host kept');
assert.strictEqual(run('/claims/', 'www.example.org'), '301 https://example.org/claims/', 'www goes to the apex first');

console.log('viewer_request: ' + (cases.length + 3) + ' cases pass');
