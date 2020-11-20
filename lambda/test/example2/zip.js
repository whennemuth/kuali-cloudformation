var AdmZip = require('adm-zip');
var fs = require("fs");

var json = fs.readFileSync('./package.json', 'utf-8')
var pkgjson = JSON.parse(json);
var zip = new AdmZip();
for (const key in pkgjson.dependencies) {
  var dir = 'node_modules/' + key;
  if(fs.existsSync(dir)) {
    console.log('Adding ' + dir + ' to zip file...');
    zip.addLocalFolder(dir, dir);
  }
};

console.log('Adding package.json to zip file...');
zip.addLocalFile("package.json");
console.log('Adding cleanup.js to zip file...')
zip.addLocalFile("cleanup.js");
zip.writeZip("./cleanup.zip");