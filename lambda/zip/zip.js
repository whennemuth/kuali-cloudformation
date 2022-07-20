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
    if(fs.existsSync(filepath)) {
      console.log(`Adding ${filepath} to zip file...`);
      zip.addLocalFile(filepath);
    }
    else {
      console.log(`${filepath} is not a file, skipping...`);
    }
  };
  this.addDirectory = (ext, dirpath) => {
    if(fs.existsSync(dirpath)) {
      console.log(`Adding ${dirpath} directory and all ${ext} content to zip file...`);
      let re = new RegExp(`.*\.${ext}$`, 'i');
      zip.addLocalFolder(dirpath, dirpath, re);
    }
    else {
      console.log(`${dirpath} is not a directory, skipping...`);
    }
  }
  this.addFilesOfType = (ext, root) => {
    let re = new RegExp(`.*\.${ext}$`, 'i');
    let files = fs.readdirSync(root).filter(file => {
      var jsfile = re.test(file);
      var dir = fs.statSync(root + '/' + file).isDirectory();
      var nm = (file == 'node_modules' || file == './node_modules');
      var vs = (file == '.vscode' || file == './.vscode');
      var qualifiedDir = (dir && ! nm && ! vs);
      return (jsfile || qualifiedDir);
    });
    files.forEach(f => {
      if(fs.statSync(f).isDirectory()) {
        this.addDirectory(ext, f);
      }
      else {
        this.addFile(f);
      }      
    });
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
    zipFile.addFilesOfType(ext, '.');
  }
  else {
    zipFile.addFile(file);
  } 
});
zipFile.write();
