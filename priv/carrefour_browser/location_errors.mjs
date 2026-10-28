// Only bounded operational details leave the browser process, never addresses,
// coordinates, provider responses or raw exception messages.
const phases={
  loading_store:'Loading the supermarket website…',
  opening_location:'Opening the store location selector…',
  loading_map:'Waiting for the store’s address map…',
  reverse_geocoding:'Finding an address near your location…',
  autocomplete:'Looking up the address in the store…',
  candidate_geocoding:'Checking nearby address suggestions…',
  selecting_address:'Selecting the nearby address…',
  saving_location:'Saving the location with the store…',
  verifying_location:'Verifying the saved store location…',
  retaining_location:'Checking that the store retains your location…'
};
export const locationProgress=stage=>phases[stage]||phases.opening_location;
export function locationFailure(store,error) {
  const stage=Object.hasOwn(phases,error.locationStage)?error.locationStage:'opening_location';
  const messages={
    loading_store:'could not load its website',
    opening_location:'could not open its location selector',
    loading_map:'could not load its address map',
    reverse_geocoding:'could not resolve an address near your location',
    autocomplete:'returned no usable address suggestions',
    candidate_geocoding:'returned no address suggestions close enough to your location',
    selecting_address:'could not select the verified address suggestion',
    saving_location:'did not finish saving the selected location',
    verifying_location:'did not confirm the selected location',
    retaining_location:'did not retain the selected location after navigation'
  };
  const errorCode=/REQUEST_DENIED|OVER_QUERY_LIMIT|PERMISSION_DENIED/.test(error.message||'')?'map_service_rejected':error.name==='TimeoutError'?'location_timeout':['location_not_saved','address_not_found','location_unconfirmed','map_timeout'].includes(error.message)?error.message:'location_setup_failed';
  const label={carrefour:'Carrefour',quickmart:'Quickmart',naivas:'Naivas',foodplus:'Foodplus'}[store]||'The store';
  return {stage,error:errorCode,message:`${label} ${messages[stage]}. Retry location to try again automatically; other stores can continue.`};
}
