export function storefront(store, {price='62.00',extra=false,max=50}={}) {
  const script=`<script>
  let qty=Number(localStorage.getItem('qty')||0);
  let extra=Number(localStorage.getItem('extra')??${extra?1:0});
  function set(n){qty=n;localStorage.setItem('qty',String(qty));render();}
  function cartSet(n){document.querySelectorAll('[data-counter]').forEach(e=>e.textContent='');setTimeout(()=>set(n),250);}
  function removeExtra(){extra=0;localStorage.setItem('extra','0');render();}
  function render(){document.querySelectorAll('[data-counter]').forEach(e=>e.textContent=String(qty));document.querySelectorAll('input.qty-input').forEach(e=>e.value=String(qty));document.querySelectorAll('[data-add]').forEach(e=>e.style.display=qty?'none':'');document.querySelectorAll('[data-qty],[data-cart-row]').forEach(e=>e.style.display=qty?'':'none');document.querySelectorAll('[data-extra-row]').forEach(e=>e.style.display=extra?'':'none');document.querySelectorAll('[data-empty]').forEach(e=>e.style.display=qty||extra?'none':'');document.querySelectorAll('[data-total]').forEach(e=>e.textContent='KES '+(qty*${Number(price)}).toFixed(2));document.querySelectorAll('.selected-quantity[data-current]').forEach(e=>e.textContent='Quantity: '+qty);document.querySelectorAll('[data-plus]').forEach(e=>e.disabled=qty>=${max});}
  window.addEventListener('DOMContentLoaded',render);
  </script>`;
  const checkout=`<button id="pay" onclick="localStorage.setItem('paid','yes')">Checkout and pay</button>`;
  const empty=`<p data-empty>Your cart is empty</p>`;
  if(store==='carrefour')return script+`<main><div class="relative grid"><h1>Milk 500ml</h1><div class="force-ltr">KES ${price}</div><div class="flex flex-col gap-sm">Get It Delivered By<button data-add onclick="set(1)">Add to cart</button><div data-qty><button onclick="set(qty-1)"><svg data-testid="minus-icon"></svg></button><span role="combobox" data-counter>0</span><button data-plus onclick="set(qty+1)"><svg data-testid="plus-icon"></svg></button></div></div></div><div id="cart-row" data-cart-row><a href="/mafken/en/milk/p/42">Milk</a><div data-testid="expanded-widget"><button aria-label="Decrease quantity" onclick="cartSet(qty-1)"><img alt="" src="data:,minus"></button><span data-counter>0</span><button aria-label="Increase quantity" data-plus onclick="set(qty+1)">+</button></div><div class="items-baseline" data-total>KES 0.00</div></div>${extra?'<div data-extra-row><a href="/mafken/en/old/p/99">Old unrelated product</a><div data-testid="expanded-widget"><button aria-label="Decrease quantity" onclick="removeExtra()">-</button><span>1</span></div><div class="items-baseline">KES 10.00</div></div>':''}${empty}<div class="group"><a href="/mafken/en/recommendation/p/777">Recommended product</a><button>Add to cart</button></div>${checkout}</main>`;
  if(store==='quickmart')return script+`<div class="js-location-address">Nairobi, Kenya</div><a href="/shops/report-spam/73">Branch</a><div id="products-listing"><div class="productInfoJs product-description"><h1>Milk 500ml</h1><a class="products-title" href="/milk">Milk</a><span class="products-price-new">KES ${price}</span><form id="frmBuyProduct"><button type="button" data-add name="btnAddToCart" onclick="set(1)">Add</button><div class="quantityBlockJs" data-qty><input class="qty-input" data-key="42" value="0"><button type="button" class="increase-js" onclick="set(qty+1)">+</button><button type="button" class="decrease-js" onclick="set(qty-1)">-</button></div></form></div></div><button class="button-cart" onclick="document.querySelector('#sideCartJs').hidden=false">Cart</button><ul id="sideCartJs" hidden><li class="list-cart-item" data-cart-row><a class="product-profile-title" href="/milk">Milk</a><span class="selected-quantity" data-current>Quantity: 0</span><span class="products-price-new">KES ${price}</span><button aria-label="Remove" onclick="set(0)">Remove</button></li>${extra?'<li class="list-cart-item" data-extra-row><a class="product-profile-title" href="/old">Old unrelated product</a><span class="selected-quantity">Quantity: 1</span><button aria-label="Remove" onclick="removeExtra()">Remove</button></li>':''}${empty}</ul>${checkout}`;
  return script+`<main><span class="geoLocation">Nairobi, Kenya</span><div class="border-naivas-bg"><input name="product_id" value="42"><a href="/milk"><span class="line-clamp-2">Milk</span></a><div class="product-price"><span class="font-bold">KES ${price}</span></div><form><button type="button" data-add onclick="set(1)">ADD TO CART</button></form><button data-qty data-counter>0</button></div><div class="rounded-xl p-4 w-full" data-cart-row><a wire:click="redirectToProductPage(42)" href="/milk">Milk</a><span x-text="quantity" data-counter>0</span><span class="font-extrabold" data-total>KES 0.00</span><a href="#" wire:click="updateQuantity(42, 'increment')" onclick="event.preventDefault();set(qty+1)">+</a><a href="#" wire:click="updateQuantity(42, 'decrement')" onclick="event.preventDefault();set(qty-1)">-</a></div>${extra?'<div class="rounded-xl p-4 w-full" data-extra-row><a wire:click="redirectToProductPage(99)" href="/old">Old unrelated product</a><span x-text="quantity">1</span><a href="#" wire:click="updateQuantity(99, \'decrement\')" onclick="event.preventDefault();removeExtra()">-</a></div>':''}${empty}${checkout}</main>`;
}

// Two real reported SKUs, plus an old cart line. State spans retailer navigations.
export function carrefourOrderFixture(currentId) {
  const items=[
    {id:'38605',name:'Del Monte Tropical Blend Juice 1L',price:265},
    {id:'120137',name:'Pepsodent Herbal Toothpaste Twin Pack 2x150g',price:374},
    {id:'99',name:'Old unrelated product',price:100}
  ];
  const current=items.find(item=>item.id===currentId);
  const script=`<script>
    const basket=JSON.parse(localStorage.getItem('basket')||'{"99":2,"120137":5}');
    const changes=JSON.parse(localStorage.getItem('changes')||'[]');
    function set(id,n){changes.push({id,before:{...basket},quantity:n});basket[id]=n;localStorage.setItem('basket',JSON.stringify(basket));localStorage.setItem('changes',JSON.stringify(changes));render();}
    function render(){
      document.querySelectorAll('[data-row]').forEach(row=>{const id=row.dataset.row;row.hidden=!basket[id];row.querySelector('[data-cart-counter]').textContent=String(basket[id]||0);row.querySelector('[data-total]').textContent=((basket[id]||0)*Number(row.dataset.price)).toFixed(2);});
      const id=${JSON.stringify(currentId || '')},qty=basket[id]||0;
      const add=document.querySelector('[data-add]'),counter=document.querySelector('[data-quantity]');
      if(add)add.hidden=Boolean(qty);if(counter){counter.hidden=!qty;counter.querySelector('[role="combobox"]').textContent=String(qty);}
      document.querySelector('[data-empty]').hidden=Object.values(basket).some(q=>q>0);
    }
    addEventListener('DOMContentLoaded',render);
  </script>`;
  const product=current?`<div class="relative grid"><h1>${current.name}</h1><div class="force-ltr">KES ${current.price}.00</div><div class="flex flex-col gap-sm">Get It Delivered By<button data-add onclick="set('${current.id}',1)">Add to cart</button><div data-quantity><button onclick="set('${current.id}',basket['${current.id}']-1)"><svg data-testid="minus-icon"></svg></button><span role="combobox"></span><button onclick="set('${current.id}',basket['${current.id}']+1)"><svg data-testid="plus-icon"></svg></button></div></div></div>`:'';
  const rows=items.map(item=>`<div data-row="${item.id}" data-price="${item.price}"><a href="/mafken/en/p/${item.id}">${item.name}</a><div data-testid="expanded-widget"><button aria-label="Decrease quantity" onclick="set('${item.id}',basket['${item.id}']-1)">-</button><span data-cart-counter></span><button aria-label="Increase quantity" onclick="set('${item.id}',basket['${item.id}']+1)">+</button></div><div class="items-baseline">KES <span data-total></span>${item.id==='38605'?'<s>299.00</s>':''}</div></div>`).join('');
  return script+`<main>${product}${rows}<p data-empty>Your Cart is Empty!</p></main>`;
}

export function naivasReact({address='Gateway Mall',price='62.00'}={}) {
  return `<header><button data-slot="dropdown-menu-trigger"><span class="truncate">${address}</span></button><button data-slot="button" id="cart" onclick="document.querySelector('#sheet').hidden=false"><svg></svg><span id="count">0</span></button></header>
  <main><div><h1>Milk 500ml</h1><div class="font-semibold">KES ${price}</div></div><img src="https://cdn.test/product/42/milk.jpg"><button onclick="qty=1;render()">Add to Cart</button></main>
  <div role="dialog" data-slot="sheet-content" id="sheet" hidden><h2>Shopping Cart</h2><button data-slot="sheet-close" onclick="document.querySelector('#sheet').hidden=true">Close</button><button data-slot="button" onclick="document.querySelector('#confirm').hidden=false">Clear Cart</button><div id="rows"></div></div>
  <div role="dialog" id="confirm" hidden><button onclick="qty=0;extra=false;render();document.querySelector('#confirm').hidden=true">Yes, clear cart</button></div>
  <button onclick="localStorage.setItem('paid','true')">Checkout and pay</button>
  <script>let qty=Number(localStorage.getItem("qty")||0),extra=localStorage.getItem("extra")!=="0";
  function row(id,n){return '<div><img src="https://cdn.test/product/'+id+'/milk.jpg"><div><p class="truncate">Milk 500ml</p><p>KES ${price}</p></div><div><button aria-label="Decrease quantity" onclick="qty--;render()">-</button><button aria-label="Open quantity selection modal">'+n+'</button><button aria-label="Increase quantity" onclick="qty++;render()">+</button></div></div>';}
  function render(){localStorage.setItem('qty',String(qty));localStorage.setItem('extra',extra?'1':'0');document.querySelector('#count').textContent=qty+(extra?1:0);document.querySelector('#rows').innerHTML=(qty?row('42',qty):'')+(extra?row('99',1):'')+(!qty&&!extra?'<p>Your cart is empty</p>':'');}render();</script>`;
}
