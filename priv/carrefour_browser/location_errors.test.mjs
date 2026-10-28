import test from 'node:test';
import assert from 'node:assert/strict';
import {locationFailure,locationProgress} from './location_errors.mjs';
test('map failures explain the failed stage without raw provider details',()=>{
  const error=Object.assign(Error('REQUEST_DENIED private-address secret-token'),{locationStage:'reverse_geocoding'});
  const failure=locationFailure('carrefour',error);
  assert.equal(failure.error,'map_service_rejected');
  assert.equal(failure.stage,'reverse_geocoding');
  assert.match(failure.message,/Carrefour could not resolve an address/);
  assert.doesNotMatch(JSON.stringify(failure),/private-address|secret-token|REQUEST_DENIED/);
});
test('unknown stages and failures are bounded, with actionable retry guidance',()=>{
  const failure=locationFailure('naivas',Object.assign(Error('private-details'),{locationStage:'private-stage'}));
  assert.equal(failure.stage,'opening_location');
  assert.match(failure.message,/Retry location/);
  assert.doesNotMatch(JSON.stringify(failure),/private/);
  assert.match(locationProgress('saving_location'),/Saving/);
});
test('timeouts retain the operation stage',()=>{
  const failure=locationFailure('naivas',Object.assign(Error('raw selector'),{name:'TimeoutError',locationStage:'saving_location'}));
  assert.equal(failure.error,'location_timeout');
  assert.match(failure.message,/did not finish saving/);
});
