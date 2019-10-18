
'use strict';

const path = require('path');
const express = require('express');
const fs = require('fs');
const PORT = 8080;
const app = express();

app.use('/static_files', express.static(path.join(__dirname, 'static_files')))

app.listen(PORT);

app.get('/*', (req, res) => {
    console.log("sending "+path.join(__dirname+'/index.html'))
    res.sendFile(path.join(__dirname+'/index.html'));
});

console.log(new Date() + `Running on port ${PORT}`);
