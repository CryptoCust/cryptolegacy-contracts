const parse = require('lcov-parse');
const fs = require('fs');

parse('./lcov.info', function(err, data) {
  if (!fs.existsSync('coverage')) {
    fs.mkdirSync('coverage');
  }
  const res = {total: {}};
  const summary = res.total;
  ['lines', 'functions', 'branches', 'statements'].forEach(name => {
    const lcovName = name === 'statements' ? 'branches' : name;
    summary[name] = {
      total: sum(data, item => get(item, `${lcovName}.found`)),
      covered: sum(data, item => get(item, `${lcovName}.hit`)),
      skipped: 0,
    }
    const pct = summary[name]['covered'] * 100 / summary[name]['total'];
    summary[name]['pct'] = Math.round(pct * 100) / 100;
  })
  fs.writeFileSync('coverage/coverage-summary.json', JSON.stringify(res, null, 2));
  console.log('res', res);
});

function sum(arr, callback) {
  let result = 0;
  arr.forEach(item => result += callback(item));
  return result;
}
function get(obj, name) {
  let value = obj;
  name.split('.').forEach(namePart => {
    value = value[namePart];
  });
  return value;
}