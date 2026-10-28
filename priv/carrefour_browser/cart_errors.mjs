// Bounded diagnostics only: never expose browser output, URLs or exception text.
export function cartFailure(error) {
  const messages = {
    checkout_unavailable: 'Foodplus checkout is unavailable. Its website currently reports maintenance; prices and selections remain available for comparison.',
    cart_mismatch: 'The cart did not match the selected products, pack counts or prices. Review the partially filled cart before trying again.',
    price_changed: 'A product price changed. Review the partially filled cart before continuing.',
    product_redirected: 'The store opened a different product page. Review the store window before trying again.',
    invalid_basket: 'The selected basket is invalid. Review your selections and search again.',
    invalid_price: 'The store price could not be read reliably. Review the product price in the store window.',
    location_changed: 'The store delivery location changed. Close the session and confirm the location again.',
    location_unconfirmed: 'The store delivery location could not be verified. Review the location in the store window.',
    store_unavailable: 'The store page could not be loaded. Review the store window and connection before trying again.',
    wrong_branch: 'The store branch does not match this basket. Review the selected branch before trying again.'
  };
  const code = Object.hasOwn(messages, error.message) ? error.message : error.name === 'TimeoutError' ? 'cart_timeout' : 'cart_controls_changed';
  const message = messages[code] || (code === 'cart_timeout'
    ? 'The store cart controls took too long to load. Products may already have been added; review the cart before trying again.'
    : 'The store cart controls could not be read. Products may already have been added; review the cart before trying again.');
  return {status: 'failed', verified: false, error: code, message};
}
