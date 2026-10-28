import test from 'node:test';
import assert from 'node:assert/strict';
import {cartFailure} from './cart_errors.mjs';

test('cart verification failures are distinct from unavailable store pages', () => {
  assert.equal(cartFailure(Error('cart_mismatch')).error, 'cart_mismatch');
  assert.equal(cartFailure(Error('store_unavailable')).error, 'store_unavailable');
  assert.match(cartFailure(Error('cart_mismatch')).message, /pack counts/);
});
test('unexpected browser exceptions expose no raw details', () => {
  const error = Error('private browser details https://example.com/secret');
  error.name = 'TimeoutError';
  assert.deepEqual(cartFailure(error), {status: 'failed', verified: false, error: 'cart_timeout', message: 'The store cart controls took too long to load. Products may already have been added; review the cart before trying again.'});
  assert.equal(cartFailure(Error('private details')).error, 'cart_controls_changed');
});
