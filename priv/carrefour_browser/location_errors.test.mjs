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

test('Naivas address form is unconfirmed rather than a delivery exclusion',()=>{
  const result=locationFailure('naivas',Error('address_details_required'));
  assert.equal(result.error,'address_details_required');
  assert.match(result.message,/full delivery address and contact details/);
  assert.doesNotMatch(result.message,/does not deliver|could not find a store/i);
});

test('store access denial is distinct from delivery coverage and excludes raw data',()=>{
  for(const store of ['quickmart','foodplus']) {
    const failure=locationFailure(store,Object.assign(Error('store_unavailable secret-query'),{locationStage:'loading_store',httpStatus:403}));
    assert.equal(failure.error,'store_access_denied');
    assert.equal(failure.http_status,403);
    assert.match(failure.message,/refused access.*HTTP 403/);
    assert.match(failure.message,/Delivery could not be checked/);
    assert.doesNotMatch(JSON.stringify(failure),/secret-query|does not deliver|could not find a store/i);
  }
});
