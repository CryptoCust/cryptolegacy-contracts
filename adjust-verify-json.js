const fs = require('fs');

const baseExcessContracts = ['Imports', 'console', 'test', 'mocks', 'UniswapV2', 'introspection']
const excessContractsByPath = {
  'Create3Factory': baseExcessContracts,
  'CryptoLegacyBuildManager': baseExcessContracts,
  'FeeRegistry': baseExcessContracts,
  'LegacyMessenger': baseExcessContracts,
  'LegacyMessenger': baseExcessContracts,
  'CryptoLegacyFactory': baseExcessContracts,
};

Object.keys(excessContractsByPath).forEach(name => {
  const fullPath = `out/${name}.sol/${name}.json`;
  if (!fs.existsSync(fullPath)) {
    return;
  }
  let solidityJson = JSON.parse(fs.readFileSync(fullPath, {encoding: 'utf8'}));

  // const excessContracts = excessContractsByPath[name];
  // Object.keys(solidityJson.sources).forEach((source) => {
  //   if (excessContracts.some(excessContractName => source.includes(excessContractName))) {
  //     delete solidityJson.sources[source];
  //   }
  // });

  solidityJson = solidityJson.metadata;
  if (!solidityJson) {
    return;
  }
  Object.keys(solidityJson.sources).forEach(path => {
    delete solidityJson.sources[path].urls;
    delete solidityJson.sources[path].license;
    delete solidityJson.sources[path].keccak256;
  });
  delete solidityJson.compiler;
  delete solidityJson.version;
  delete solidityJson.output;
  delete solidityJson.settings.compilationTarget;

  fs.writeFileSync(fullPath, JSON.stringify(solidityJson, null, ' '));
  console.log(fullPath, 'size:', fs.statSync(fullPath).size);
})
