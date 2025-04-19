const fs = require("fs");
const path = require("path");

const outputDir = "./flat";

// Modified getSolidityFiles to take an optional filterFunc
function getSolidityFiles(dir, fileList = [], filterFunc) {
  const files = fs.readdirSync(dir);
  files.forEach(file => {
    const filePath = path.join(dir, file);
    const stat = fs.statSync(filePath);
    if (stat.isDirectory()) {
      getSolidityFiles(filePath, fileList, filterFunc);
    } else if (file.endsWith(".sol")) {
      // If filterFunc is provided, only add the file if it passes the filter
      if (!filterFunc || filterFunc(file)) {
        fileList.push(filePath);
      }
    }
  });
  // Special case for the test directory
  if (dir === "./test") {
    fileList.push("./script/LibDeploy.sol");
  }
  return fileList;
}

// Remove unwanted content and cleanup Solidity file content
function cleanContent(content) {
  return content
    // Remove SPDX-License-Identifier comments
    .replace(/^\/\/\s*SPDX-License-Identifier:.*$/gm, "")
    // Remove local imports (relative paths starting with "./" or "../")
    .replace(/^import\s+{[^}]+}\s+from\s+"\.{1,2}\/.*?";\s*$/gm, "")
    .replace(/^import\s+"\.{1,2}\/.*?";\s*$/gm, "")
    .replace(/\/\*[^*]*\*+(?:[^/*][^*]*\*+)*\//g, match =>
      /copyright|file:/i.test(match) ? "" : match
    )
    .replace(/\/\/\s*File:.*/gi, "")
    .replace(/pragma solidity [^;]+;/g, (match, offset, string) =>
      string.indexOf(match) === offset ? match : ""
    )
    .replace(/\n\s*\n/g, "\n")
    .trim();
}

// Remove duplicate external import statements
function deduplicateImports(content) {
  const lines = content.split("\n");
  const seenExternalImports = new Set();
  const result = [];
  for (let line of lines) {
    if (line.trim().startsWith("import ")) {
      // Extract the import path
      const match = line.match(/import\s+(?:\{[^}]+\}\s+from\s+)?["']([^"']+)["'];/);
      if (match) {
        const importPath = match[1];
        // If the import path does not start with a dot, it's external
        if (!importPath.startsWith(".")) {
          if (seenExternalImports.has(line.trim())) {
            continue; // Skip duplicate external import
          }
          seenExternalImports.add(line.trim());
        }
      }
    }
    result.push(line);
  }
  return result.join("\n");
}

// New helper function to merge an array of Solidity files into an output file
function mergeContractsFromFiles(solidityFiles, outputFile) {
  if (!fs.existsSync(outputDir)) {
    fs.mkdirSync(outputDir, { recursive: true });
  }

  let mergedContent = "";
  let seenPragma = false;

  solidityFiles.forEach(file => {
    let content = fs.readFileSync(file, "utf8");
    // Only keep the first occurrence of a pragma
    content = content.replace(/pragma solidity [^;]+;/g, (match) => {
      if (seenPragma) return "";
      seenPragma = true;
      return match;
    });
    mergedContent += cleanContent(content) + "\n";
  });

  // Remove duplicate external import statements
  mergedContent = deduplicateImports(mergedContent);

  fs.writeFileSync(outputFile, mergedContent.trim(), "utf8");
  console.log(`Merged ${solidityFiles.length} contracts into ${outputFile}`);
}

// 1. Process contracts directory for contracts.sol,
//    excluding any file with "Mock" in its name.
const contractsFiles = getSolidityFiles("./contracts", [], file => !file.includes("Mock"));
mergeContractsFromFiles(contractsFiles, path.join(outputDir, "contracts.sol"));

// 2. Process tests.sol by merging files from the test directory and
//    additionally include files from contracts that have "Mock" in their name.
const testFiles = getSolidityFiles("./test");
const mockFiles = getSolidityFiles("./contracts", [], file => file.includes("Mock"));
mergeContractsFromFiles(testFiles.concat(mockFiles), path.join(outputDir, "tests.sol"));