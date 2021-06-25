const AdmZip = require('adm-zip');
const fs = require("fs");

function PackageFile() {
  this.location = {
    pkgfile: './package.json',
    lockfile: './package-lock.json'
  };

  this.pkgfile = {};
  if(fs.existsSync(this.location.lockfile)) {
    this.pkgfile = JSON.parse(fs.readFileSync(this.location.lockfile, 'utf-8'));
  }
  else if(fs.existsSync(this.location.pkgfile)) {
    this.pkgfile = JSON.parse(fs.readFileSync(this.location.pkgfile, 'utf-8'));
  }

  this.getDependencies = () => {
    return this.pkgfile.dependencies;
  }
  this.getName = () => {
    return this.pkgfile.name;
  }
};

function ZipFile(fp) {
  const zip = new AdmZip();
  const filepath = fp;
  this.addDependencies = (dependencies) => {
    for (const key in dependencies) {
      let val = dependencies[key];
      if(typeof val === 'object') {
        if(val.dev) {
          continue;
        }
      }
      let dir = `node_modules/${key}`;
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
  this.addFilesOfType = (ext) => {
    let re = new RegExp(`.*\.${ext}$`, 'i');
    let files = fs.readdirSync('.').filter(file => re.test(file));
    files.forEach(f => this.addFile(f));
  };
  this.write = () => {
    console.log(`Writing ${filepath}...`);
    zip.writeZip(filepath);
  }
};

var args = process.argv.slice(2);
var packageFile = new PackageFile();
zipFile = new ZipFile(`./${packageFile.getName()}.zip`);
zipFile.addDependencies(packageFile.getDependencies());
zipFile.addFile('package.json');
args.forEach(file => {
  if(/^type:/.test(file)) {
    let ext = file.split(":")[1].toLocaleLowerCase();
    zipFile.addFilesOfType(ext);
  }
  else {
    zipFile.addFile(file);
  } 
});
zipFile.write();
