
'use strict';

const path = require('path');
const express = require('express');
const fs = require('fs');
const PORT = 8080;
const HOST = 'localhost';
const http = require('http');
const https = require('https');

const key = fs.readFileSync('ssl/private.key');
const cert = fs.readFileSync( 'ssl/localhost.crt' );

const options = {
  key: key,
  cert: cert
};

const app = express();

http.createServer(app).listen(PORT);
https.createServer(options, app).listen(443);

app.use(function(req, res, next) {
  if (req.secure) {
    next();
  } 
  else {
    // Get the host and strip away the port if included.
    var host = req.headers.host.split(":")[0];
    console.log('request is NOT secure. Redirecting to https://' + host + req.url)
    res.redirect('https://' + host + req.url);
  }
});

app.use('/static_files', express.static(path.join(__dirname, 'static_files')))

app.get('/*', (req, res) => {
    console.log("sending "+path.join(__dirname+'/index.html'))
    res.sendFile(path.join(__dirname+'/index.html'));
});

console.log(new Date() + `Running on http://${HOST}:${PORT}`);
