const express = require('express');
const cors = require('cors');
require('dotenv').config();

const app = express();
app.use(cors());
app.use(express.json());

const PORT = process.env.PORT || 3000;
const KROGER_BASE_URL = 'https://api.kroger.com/v1';
const KROGER_OAUTH_URL = 'https://api.kroger.com/v1/connect/oauth2/token';

const KROGER_CLIENT_ID = process.env.KROGER_CLIENT_ID || '';
const KROGER_CLIENT_SECRET = process.env.KROGER_CLIENT_SECRET || '';
const KROGER_REDIRECT_URI = process.env.KROGER_REDIRECT_URI || 'https://budgetbites.example.com/callback';
const APPLE_APP_ID = process.env.APPLE_APP_ID || 'TEAM123456.com.budgetbites.app';

// In-memory 24-hour cache for prices and client-credentials token
let clientTokenCache = { token: null, expiresAt: 0 };
const priceCache = new Map(); // locationId -> { timestamp, data }
const CACHE_DURATION_MS = 24 * 60 * 60 * 1000; // 24 hours

// 1. Apple App Site Association for iOS Universal Links
const aasaPayload = {
  applinks: {
    apps: [],
    details: [
      {
        appID: APPLE_APP_ID,
        paths: ["/callback", "/callback/*"]
      }
    ]
  }
};

app.get(['/.well-known/apple-app-site-association', '/apple-app-site-association'], (req, res) => {
  res.setHeader('Content-Type', 'application/json');
  res.status(200).send(JSON.stringify(aasaPayload));
});

// Helper: Get Kroger Client Credentials Token (for search, locations, prices)
async function getClientCredentialsToken() {
  const now = Date.now();
  if (clientTokenCache.token && clientTokenCache.expiresAt > now + 60000) {
    return clientTokenCache.token;
  }

  if (!KROGER_CLIENT_ID || !KROGER_CLIENT_SECRET) {
    throw new Error('Kroger Client ID or Secret is not configured in backend environment.');
  }

  const credentials = Buffer.from(`${KROGER_CLIENT_ID}:${KROGER_CLIENT_SECRET}`).toString('base64');
  const params = new URLSearchParams();
  params.append('grant_type', 'client_credentials');
  params.append('scope', 'product.compact');

  const response = await fetch(KROGER_OAUTH_URL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
      'Authorization': `Basic ${credentials}`
    },
    body: params.toString()
  });

  if (!response.ok) {
    const errText = await response.text();
    throw new Error(`Failed to acquire Kroger client token (${response.status}): ${errText}`);
  }

  const data = await response.json();
  clientTokenCache = {
    token: data.access_token,
    expiresAt: now + (data.expires_in * 1000)
  };
  return clientTokenCache.token;
}

// 2. Locations API: Find nearby stores by ZIP or Lat/Lon
app.get('/api/kroger/locations', async (req, res) => {
  try {
    const { zipCode, lat, lon } = req.query;
    if (!zipCode && (!lat || !lon)) {
      return res.status(400).json({ error: 'Please provide either zipCode or lat & lon query parameters.' });
    }

    const token = await getClientCredentialsToken();
    const url = new URL(`${KROGER_BASE_URL}/locations`);
    url.searchParams.append('filter.limit', '10');

    if (zipCode) {
      url.searchParams.append('filter.zipCode.near', zipCode);
    } else {
      url.searchParams.append('filter.latLong.near', `${lat},${lon}`);
    }

    const response = await fetch(url.toString(), {
      headers: {
        'Authorization': `Bearer ${token}`,
        'Accept': 'application/json'
      }
    });

    if (!response.ok) {
      const errText = await response.text();
      return res.status(response.status).json({ error: `Kroger Locations API error: ${errText}` });
    }

    const data = await response.json();
    const stores = (data.data || []).map(store => ({
      locationId: store.locationId,
      name: store.name || 'Kroger',
      chain: store.chain || 'KROGER',
      address: {
        addressLine1: store.address?.addressLine1 || '',
        city: store.address?.city || '',
        state: store.address?.state || '',
        zipCode: store.address?.zipCode || ''
      },
      phone: store.phone || '',
      distance: store.distance ? parseFloat(store.distance.toFixed(1)) : null
    }));

    res.json({ stores });
  } catch (err) {
    console.error('Error fetching locations:', err);
    res.status(500).json({ error: err.message });
  }
});

// App ingredient definitions with preferred search keywords for Kroger Products API
const APP_INGREDIENTS = {
  eggs: { term: "large eggs", minSize: 12 },
  oats: { term: "rolled oats", minSize: 16 },
  banana: { term: "bananas", minSize: 1 },
  milk: { term: "2% reduced fat milk half gallon", minSize: 64 },
  yog: { term: "plain nonfat greek yogurt 32 oz", minSize: 32 },
  chick: { term: "boneless skinless chicken breasts", minSize: 16 },
  turk: { term: "93% lean ground turkey 1 lb", minSize: 16 },
  tuna: { term: "chunk light tuna in water can 5 oz", minSize: 5 },
  bean: { term: "black beans 15 oz can", minSize: 15 },
  lent: { term: "brown lentils dry 16 oz", minSize: 16 },
  rice: { term: "brown rice 1 lb", minSize: 16 },
  bread: { term: "100% whole wheat bread loaf", minSize: 20 },
  sweet: { term: "sweet potato", minSize: 1 },
  pasta: { term: "whole wheat spaghetti 16 oz", minSize: 16 },
  broc: { term: "frozen broccoli florets 12 oz", minSize: 12 },
  spin: { term: "frozen chopped spinach 10 oz", minSize: 10 },
  mix: { term: "frozen mixed vegetables 12 oz", minSize: 12 },
  carrot: { term: "whole carrots 1 lb bag", minSize: 16 },
  tom: { term: "diced tomatoes 14.5 oz can", minSize: 14.5 },
  onion: { term: "yellow onion", minSize: 1 },
  pb: { term: "creamy peanut butter 16 oz", minSize: 16 },
  oil: { term: "pure olive oil 16 oz", minSize: 16 },
  apple: { term: "gala apples", minSize: 1 },
  ched: { term: "sharp cheddar cheese block 8 oz", minSize: 8 },
  tort: { term: "whole wheat tortillas 8 count", minSize: 8 },
  whey: { term: "whey protein powder vanilla", minSize: 30 },
  cott: { term: "low fat cottage cheese 16 oz", minSize: 16 },
  berry: { term: "frozen mixed berries 12 oz", minSize: 12 },
  salmon: { term: "wild caught salmon fillet", minSize: 16 },
  avocado: { term: "hass avocado", minSize: 1 },
  almond: { term: "whole almonds 8 oz", minSize: 8 },
  quinoa: { term: "white quinoa dry 12 oz", minSize: 12 },
  tea: { term: "black tea bags 20 ct", minSize: 20 },
  coffee: { term: "ground coffee medium roast 12 oz", minSize: 12 },
  sparkling: { term: "sparkling water 12 pack cans", minSize: 12 },
  soda: { term: "prebiotic soda 12 oz can", minSize: 12 },
  wine: { term: "dry red wine 750 ml", minSize: 1 }
};

// 3. Products/Prices API: Fetch live prices for all ingredients at chosen store
app.get('/api/kroger/prices', async (req, res) => {
  try {
    const { locationId } = req.query;
    if (!locationId) {
      return res.status(400).json({ error: 'locationId is required to fetch store prices.' });
    }

    // Check 24-hour cache
    const cached = priceCache.get(locationId);
    if (cached && (Date.now() - cached.timestamp < CACHE_DURATION_MS)) {
      return res.json({
        locationId,
        cached: true,
        updatedAt: new Date(cached.timestamp).toISOString(),
        prices: cached.data
      });
    }

    const token = await getClientCredentialsToken();
    const results = {};

    // Fetch products in parallel with rate-limit batching (batches of 6)
    const ingredientKeys = Object.keys(APP_INGREDIENTS);
    const batchSize = 6;

    for (let i = 0; i < ingredientKeys.length; i += batchSize) {
      const batch = ingredientKeys.slice(i, i + batchSize);
      await Promise.all(batch.map(async (key) => {
        try {
          const cfg = APP_INGREDIENTS[key];
          const url = new URL(`${KROGER_BASE_URL}/products`);
          url.searchParams.append('filter.term', cfg.term);
          url.searchParams.append('filter.locationId', locationId);
          url.searchParams.append('filter.limit', '3');

          const response = await fetch(url.toString(), {
            headers: {
              'Authorization': `Bearer ${token}`,
              'Accept': 'application/json'
            }
          });

          if (!response.ok) return;

          const data = await response.json();
          const items = data.data || [];
          if (!items.length) return;

          // Pick the best match with price info
          for (const item of items) {
            const priceInfo = item.items?.[0]?.price;
            if (priceInfo && (priceInfo.regular || priceInfo.promo)) {
              const regular = priceInfo.regular || priceInfo.promo;
              const promo = priceInfo.promo > 0 && priceInfo.promo < regular ? priceInfo.promo : null;
              const price = promo !== null ? promo : regular;
              const size = item.items?.[0]?.size || '';
              const upc = item.upc || item.items?.[0]?.itemId || '';

              results[key] = {
                upc,
                name: item.description || cfg.term,
                size,
                regularPrice: regular,
                promoPrice: promo,
                price: price,
                isPromo: promo !== null,
                inStock: item.items?.[0]?.inventory?.stockLevel !== 'TEMPORARILY_OUT_OF_STOCK'
              };
              break;
            }
          }
        } catch (itemErr) {
          console.warn(`Could not fetch price for ${key}:`, itemErr.message);
        }
      }));
    }

    const payload = {
      timestamp: Date.now(),
      data: results
    };
    priceCache.set(locationId, payload);

    res.json({
      locationId,
      cached: false,
      updatedAt: new Date(payload.timestamp).toISOString(),
      prices: results
    });
  } catch (err) {
    console.error('Error fetching prices:', err);
    res.status(500).json({ error: err.message });
  }
});

// 4. OAuth Token Exchange (PKCE Authorization Code Flow)
app.post('/api/kroger/oauth/token', async (req, res) => {
  try {
    const { code, code_verifier, redirect_uri } = req.body;
    if (!code || !code_verifier) {
      return res.status(400).json({ error: 'code and code_verifier are required for PKCE token exchange.' });
    }

    const redirectUri = redirect_uri || KROGER_REDIRECT_URI;
    const credentials = Buffer.from(`${KROGER_CLIENT_ID}:${KROGER_CLIENT_SECRET}`).toString('base64');

    const params = new URLSearchParams();
    params.append('grant_type', 'authorization_code');
    params.append('code', code);
    params.append('code_verifier', code_verifier);
    params.append('redirect_uri', redirectUri);

    const response = await fetch(KROGER_OAUTH_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Authorization': `Basic ${credentials}`
      },
      body: params.toString()
    });

    const data = await response.json();
    if (!response.ok) {
      return res.status(response.status).json({ error: data.error_description || 'OAuth token exchange failed' });
    }

    // Return tokens securely to the app (app will store them in iOS Keychain)
    res.json({
      access_token: data.access_token,
      refresh_token: data.refresh_token,
      expires_in: data.expires_in,
      token_type: data.token_type
    });
  } catch (err) {
    console.error('OAuth token exchange error:', err);
    res.status(500).json({ error: err.message });
  }
});

// 5. OAuth Token Refresh
app.post('/api/kroger/oauth/refresh', async (req, res) => {
  try {
    const { refresh_token } = req.body;
    if (!refresh_token) {
      return res.status(400).json({ error: 'refresh_token is required.' });
    }

    const credentials = Buffer.from(`${KROGER_CLIENT_ID}:${KROGER_CLIENT_SECRET}`).toString('base64');
    const params = new URLSearchParams();
    params.append('grant_type', 'refresh_token');
    params.append('refresh_token', refresh_token);

    const response = await fetch(KROGER_OAUTH_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Authorization': `Basic ${credentials}`
      },
      body: params.toString()
    });

    const data = await response.json();
    if (!response.ok) {
      return res.status(response.status).json({ error: data.error_description || 'OAuth token refresh failed' });
    }

    res.json({
      access_token: data.access_token,
      refresh_token: data.refresh_token || refresh_token,
      expires_in: data.expires_in
    });
  } catch (err) {
    console.error('OAuth refresh error:', err);
    res.status(500).json({ error: err.message });
  }
});

// 6. Send Items to Kroger Cart
app.put('/api/kroger/cart', async (req, res) => {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({ error: 'Missing or invalid user Bearer access token.' });
    }

    const { items } = req.body;
    if (!items || !Array.isArray(items) || !items.length) {
      return res.status(400).json({ error: 'items array is required (each item must have upc and quantity).' });
    }

    const formattedItems = items.map(it => ({
      upc: String(it.upc).padStart(13, '0'), // Kroger standard 13-digit format
      quantity: Math.max(1, parseInt(it.quantity, 10) || 1)
    }));

    const response = await fetch(`${KROGER_BASE_URL}/cart/add`, {
      method: 'PUT',
      headers: {
        'Authorization': authHeader,
        'Content-Type': 'application/json',
        'Accept': 'application/json'
      },
      body: JSON.stringify({ items: formattedItems })
    });

    if (!response.ok) {
      const errText = await response.text();
      return res.status(response.status).json({ error: `Kroger Cart API error (${response.status}): ${errText}` });
    }

    res.status(200).json({
      success: true,
      itemCount: formattedItems.length,
      message: 'Items successfully added to Kroger cart'
    });
  } catch (err) {
    console.error('Add to cart error:', err);
    res.status(500).json({ error: err.message });
  }
});

// 7. Universal Link Callback Handler for ASWebAuthenticationSession
app.get('/callback', (req, res) => {
  const { code, state, error, error_description } = req.query;

  if (error) {
    return res.status(400).send(`
      <!DOCTYPE html>
      <html><head><title>Authorization Failed</title></head>
      <body style="font-family:system-ui;text-align:center;padding:40px;">
        <h2>Authentication Failed</h2>
        <p>${error_description || error}</p>
        <p>You can close this window and return to BudgetBites.</p>
      </body></html>
    `);
  }

  // When ASWebAuthenticationSession intercepts this URL, it extracts the code and state
  res.send(`
    <!DOCTYPE html>
    <html><head><title>BudgetBites Connected</title></head>
    <body style="font-family:system-ui;text-align:center;padding:40px;">
      <h2>Connecting to Kroger...</h2>
      <p>Returning to BudgetBites.</p>
      <script>
        // Smoothly close browser or redirect to universal app link
        window.location.href = "budgetbites://callback?code=${code}&state=${state}";
      </script>
    </body></html>
  `);
});

app.listen(PORT, () => {
  console.log(`BudgetBites Kroger backend server running on port ${PORT}`);
});
