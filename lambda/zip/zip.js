var AdmZip = require('adm-zip');
var fs = require("fs");

const packageFile = {
  location: './package.json',
  exists: () => {
    return fs.existsSync(packageFile.location);
  },
  asObject: () => {
    if(packageFile.exists()) {
      var json = fs.readFileSync(packageFile.location, 'utf-8');
      return JSON.parse(json);
    }
    return {};
  },
  getName: () => {
    return packageFile.asObject().name;
  },
  getDependencies: () => {
    return packageFile.asObject().dependencies;
  }
};

function ZipFile(fp) {
  const zip = new AdmZip();
  const filepath = fp;
  this.addDependencies = (dependencies) => {
    for (const key in dependencies) {
      var dir = `node_modules/${key}`;
      if(fs.existsSync(dir)) {
        console.log(`Adding ${dir} to zip file...`);
        zip.addLocalFolder(dir, dir);
      }
    }
  };
  this.addFile = (filepath) => {
    console.log(`Adding ${filepath} to zip file...`);
    zip.addLocalFile(filepath);
  };
  this.write = () => {
    console.log(`Writing ${filepath}...`);
    zip.writeZip(filepath);
  }
};

var args = process.argv.slice(2);
zipFile = new ZipFile(`./${packageFile.getName()}.zip`);
zipFile.addDependencies(packageFile.getDependencies());
zipFile.addFile('package.json');
args.forEach(file => {
  zipFile.addFile(file);
});
zipFile.write();
