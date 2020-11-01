module.exports = {
  SUCCESS: 'SUCCESS',
  FAILURE: 'FAILURE',
  send: (event, context, status, data) => {
    console.log('Sending ' + status + ' response, data: ' + JSON.stringify(data));
  }
};