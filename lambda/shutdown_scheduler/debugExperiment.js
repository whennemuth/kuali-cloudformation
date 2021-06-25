
const parser = require('cron-parser');

exports.runTrial = function(trialName, trialArg) {

  this.trial1 = () => {
    let tz = 'America/New_York';
    let hereDate = new Date();
    hereDate.setMilliseconds(0);
    let thereDateStr = hereDate.toLocaleString('en-US', {timeZone: tz});
    let thereDate = new Date(thereDateStr);
    let UTCDateStr = hereDate.toLocaleString('en-US', {timeZone: 'UTC'});
    let UTCDate = new Date(UTCDateStr);
    let diff = thereDate.getTime() - UTCDate.getTime();
    let diffHrs = diff /1000 /60 /60;
    diffHrs = diffHrs > 0 ? `+${diffHrs}` : diffHrs+''
    if(diffHrs.length == 2) {
      diffHrs = diffHrs.slice(0, 1) + '0' + diffHrs.slice(1);
    }
    let GMTOffset = `GMT${diffHrs}00`
    let sampleDateStr = '6/24/2021, 12:48:31 AM';
    let sampleDate = new Date(`${sampleDateStr} ${GMTOffset}`);
    console.log(sampleDate);
  }

  this.trial2 = () => {

    let hereDate = new Date();
    hereDate.setMilliseconds(0);

    const
      tz = 'America/New_York',
      hereOffset = hereDate.getTimezoneOffset() * 60 * -1000,
      thereStr = hereDate.toLocaleString('en-US', {timeZone: tz}),
      thereDate = new Date(thereStr),
      diff = (thereDate.getTime() - hereDate.getTime()),
      localeOffset = hereOffset + diff,
      localeOffsetHrs = localeOffset /1000 /60 /60;

      retval = {
        hereDate: hereDate,
        hereOffset: hereOffset,
        thereStr: thereStr,
        thereDate: thereDate,
        diff: diff,
        localeOffset: localeOffset * -1 ,
        localeOffsetHrs: localeOffsetHrs * -1 ,
        toDateString: `${thereDate} UTC${(localeOffset < 0 ? '' : '+')+localeOffsetHrs}`
      };

      console.log(JSON.stringify(retval, null, 2));
  }

  this[trialName](trialArg);
};