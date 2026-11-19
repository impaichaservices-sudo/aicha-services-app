// AÏCHA SERVICES — serveur de notifications push (Cloudflare Worker, gratuit).
//
// Variables à créer dans Cloudflare (Worker → Settings → Variables and Secrets) :
//   SERVICE_ACCOUNT   (Secret)  : tout le contenu du fichier JSON de la clé
//                                 « compte de service » Firebase
//   SUPER_UIDS        (Text)    : UID du Super Admin (plusieurs : séparés par des virgules)
//
// L'application envoie : { action, title, body, data, ... } avec l'en-tête
// Authorization: Bearer <jeton Firebase de l'utilisateur>.
//   action = 'to_staff' : prévenir l'équipe d'une boutique (shopId)
//   action = 'to_user'  : prévenir un client (uid, kind = 'orders' | 'messages')
//   action = 'to_topic' : nouveautés / promotions (shops = ['all'] ou ids)

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
  'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
};

export default {
  async fetch(req, env) {
    if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
    if (req.method === 'GET') {
      return new Response('AICHA SERVICES notifications : OK', { headers: CORS });
    }
    if (req.method !== 'POST') return json({ error: 'method' }, 405);
    try {
      if (!env.SERVICE_ACCOUNT) throw httpErr(500, 'SERVICE_ACCOUNT manquant');
      const sa = JSON.parse(env.SERVICE_ACCOUNT);
      const projectId = sa.project_id;
      const idToken = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
      const uid = await verifyIdToken(idToken, projectId);
      const body = await req.json();
      const access = await getAccessToken(sa);

      const supers = (env.SUPER_UIDS || '').split(',').map((s) => s.trim()).filter(Boolean);
      const isSuper = supers.includes(uid) || (await getDoc(access, projectId, `admins/${uid}`)) !== null;
      const staffDoc = isSuper ? null : await getDoc(access, projectId, `staff/${uid}`);
      const staff = staffDoc ? fields(staffDoc) : null;
      const staffActive = !!staff && staff.active !== false;

      const message = {
        notification: { title: cut(body.title, 100), body: cut(body.body, 300) },
        data: cleanData(body.data),
        android: { priority: 'high', notification: { sound: 'default' } },
      };

      let sent = 0;
      if (body.action === 'to_staff') {
        const shop = topicSafe(body.shopId || 'main');
        sent += await send(access, projectId, {
          ...message,
          condition: `'staff_${shop}' in topics || 'staff_all' in topics`,
        });
      } else if (body.action === 'to_user') {
        if (!isSuper && !staffActive) {
          // Un client peut prévenir uniquement un membre de l'équipe
          // (discussion attribuée à un agent) ou le Super Admin.
          const target = await getDoc(access, projectId, `staff/${body.uid}`);
          if (!target && !supers.includes(body.uid)) throw httpErr(403, 'interdit');
        }
        const userDoc = await getDoc(access, projectId, `users/${body.uid}`);
        if (!userDoc) return json({ ok: true, sent: 0 });
        const user = fields(userDoc);
        const prefs = user.notif || {};
        if (body.kind && prefs[body.kind] === false) return json({ ok: true, skipped: true });
        const tokens = Array.isArray(user.fcmTokens) ? user.fcmTokens.slice(-10) : [];
        for (const token of tokens) sent += await send(access, projectId, { ...message, token });
      } else if (body.action === 'to_topic') {
        let shops = Array.isArray(body.shops) && body.shops.length ? body.shops : ['all'];
        if (!isSuper) {
          if (!staffActive) throw httpErr(403, 'interdit');
          const perms = staff.perms || {};
          if (staff.role !== 'manager' && perms.promos !== true) throw httpErr(403, 'interdit');
          shops = [staff.shopId];
        }
        const topics = shops.includes('all')
          ? ['promos_all']
          : shops.slice(0, 5).map((s) => 'promos_' + topicSafe(s));
        sent += await send(access, projectId, {
          ...message,
          condition: topics.map((t) => `'${t}' in topics`).join(' || '),
        });
      } else if (body.action === 'reset_password') {
        // Super Admin uniquement : nouveau mot de passe pour un utilisateur.
        if (!isSuper) throw httpErr(403, 'interdit');
        const pwd = String(body.password || '');
        if (!body.uid || pwd.length < 6) throw httpErr(400, 'mot de passe trop court');
        const r = await fetch(
          `https://identitytoolkit.googleapis.com/v1/projects/${projectId}/accounts:update`,
          {
            method: 'POST',
            headers: { Authorization: `Bearer ${access}`, 'Content-Type': 'application/json' },
            body: JSON.stringify({ localId: String(body.uid), password: pwd }),
          }
        );
        if (!r.ok) throw httpErr(500, 'réinitialisation impossible (' + r.status + ')');
        return json({ ok: true });
      } else if (body.action === 'incoming_call' || body.action === 'call_ended') {
        // Appel par internet : faire sonner (ou arrêter) les téléphones appelés.
        const callDoc = await getDoc(access, projectId, `calls/${body.callId}`);
        if (!callDoc) throw httpErr(404, 'appel introuvable');
        const c = fields(callDoc);
        const participant =
          c.callerId === uid || c.clientId === uid || c.answeredBy === uid ||
          isSuper || (staffActive && staff.shopId === c.shopId);
        if (!participant) throw httpErr(403, 'interdit');
        if (body.action === 'incoming_call' && c.callerId !== uid) throw httpErr(403, 'interdit');
        const data = {
          type: body.action,
          callId: String(body.callId),
          callerId: String(c.callerId || ''),
          callerName: cut(c.callerName, 80),
          conversationId: String(c.conversationId || ''),
          shopId: String(c.shopId || ''),
          timestamp: String(Date.now()),
        };
        const dataMsg = { data, android: { priority: 'high', ttl: '45s' } };
        const targets = [];
        if (c.callerRole === 'shop') {
          targets.push(c.clientId);
        } else if (c.calleeId) {
          targets.push(c.calleeId);
        }
        for (const t of targets) {
          const u = await getDoc(access, projectId, `users/${t}`);
          const tokens = u && Array.isArray(fields(u).fcmTokens) ? fields(u).fcmTokens.slice(-10) : [];
          for (const token of tokens) sent += await send(access, projectId, { ...dataMsg, token });
        }
        if (c.callerRole !== 'shop') {
          const shop = topicSafe(c.shopId || 'main');
          // Pas encore attribuée : toute l'équipe de la boutique + Super Admin.
          // Attribuée : l'agent (ci-dessus) + le Super Admin.
          const cond = !c.calleeId || body.action === 'call_ended'
            ? `'staff_${shop}' in topics || 'staff_all' in topics`
            : `'staff_all' in topics`;
          sent += await send(access, projectId, { ...dataMsg, condition: cond });
        }
      } else {
        throw httpErr(400, 'action inconnue');
      }
      return json({ ok: true, sent });
    } catch (e) {
      return json({ error: String((e && e.message) || e) }, (e && e.status) || 500);
    }
  },
};

// ---------- utilitaires ----------
function json(obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  });
}
function httpErr(status, message) {
  const e = new Error(message);
  e.status = status;
  return e;
}
function cut(s, n) {
  return String(s || '').slice(0, n);
}
function topicSafe(s) {
  return String(s).replace(/[^a-zA-Z0-9\-_.~%]/g, '_');
}
function cleanData(d) {
  const out = {};
  if (d && typeof d === 'object') {
    for (const [k, v] of Object.entries(d)) out[String(k)] = cut(v, 500);
  }
  return out;
}

// Base64 URL
function b64url(bytes) {
  let bin = '';
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
function b64urlStr(str) {
  return b64url(new TextEncoder().encode(str));
}
function b64urlDecode(s) {
  s = s.replace(/-/g, '+').replace(/_/g, '/');
  while (s.length % 4) s += '=';
  return Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
}

// ---------- vérification du jeton Firebase de l'utilisateur ----------
let jwks = null;
let jwksAt = 0;
async function verifyIdToken(token, projectId) {
  if (!token || token.split('.').length !== 3) throw httpErr(401, 'jeton manquant');
  const [h, p, s] = token.split('.');
  let header, payload;
  try {
    header = JSON.parse(new TextDecoder().decode(b64urlDecode(h)));
    payload = JSON.parse(new TextDecoder().decode(b64urlDecode(p)));
  } catch (_) {
    throw httpErr(401, 'jeton illisible');
  }
  const now = Math.floor(Date.now() / 1000);
  if (
    payload.aud !== projectId ||
    payload.iss !== `https://securetoken.google.com/${projectId}` ||
    !payload.sub ||
    payload.exp < now
  ) {
    throw httpErr(401, 'jeton invalide');
  }
  if (!jwks || Date.now() - jwksAt > 3600 * 1000) {
    const r = await fetch(
      'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com'
    );
    jwks = (await r.json()).keys || [];
    jwksAt = Date.now();
  }
  const jwk = jwks.find((k) => k.kid === header.kid);
  if (!jwk) throw httpErr(401, 'clé inconnue');
  const key = await crypto.subtle.importKey(
    'jwk',
    jwk,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['verify']
  );
  const ok = await crypto.subtle.verify(
    'RSASSA-PKCS1-v1_5',
    key,
    b64urlDecode(s),
    new TextEncoder().encode(`${h}.${p}`)
  );
  if (!ok) throw httpErr(401, 'signature invalide');
  return payload.sub;
}

// ---------- jeton d'accès Google (compte de service) ----------
let cachedToken = null;
async function getAccessToken(sa) {
  if (cachedToken && cachedToken.exp > Date.now() + 60000) return cachedToken.token;
  const now = Math.floor(Date.now() / 1000);
  const header = b64urlStr(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claim = b64urlStr(
    JSON.stringify({
      iss: sa.client_email,
      scope:
        'https://www.googleapis.com/auth/firebase.messaging https://www.googleapis.com/auth/datastore https://www.googleapis.com/auth/identitytoolkit',
      aud: 'https://oauth2.googleapis.com/token',
      iat: now,
      exp: now + 3600,
    })
  );
  const pem = sa.private_key.replace(/-----[^-]+-----/g, '').replace(/\s+/g, '');
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    'pkcs8',
    der,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign']
  );
  const sig = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(`${header}.${claim}`)
  );
  const jwt = `${header}.${claim}.${b64url(new Uint8Array(sig))}`;
  const r = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=${jwt}`,
  });
  const j = await r.json();
  if (!j.access_token) throw httpErr(500, 'connexion Google impossible : ' + JSON.stringify(j));
  cachedToken = { token: j.access_token, exp: Date.now() + (j.expires_in || 3600) * 1000 };
  return j.access_token;
}

// ---------- Firestore (lecture) ----------
async function getDoc(access, projectId, path) {
  const r = await fetch(
    `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/${path}`,
    { headers: { Authorization: `Bearer ${access}` } }
  );
  if (r.status === 404) return null;
  if (!r.ok) throw httpErr(500, 'lecture Firestore impossible (' + r.status + ')');
  return r.json();
}
function value(v) {
  if (!v || typeof v !== 'object') return undefined;
  if ('stringValue' in v) return v.stringValue;
  if ('booleanValue' in v) return v.booleanValue;
  if ('integerValue' in v) return Number(v.integerValue);
  if ('doubleValue' in v) return v.doubleValue;
  if ('nullValue' in v) return null;
  if ('timestampValue' in v) return v.timestampValue;
  if ('arrayValue' in v) return (v.arrayValue.values || []).map(value);
  if ('mapValue' in v) {
    const o = {};
    for (const [k, x] of Object.entries(v.mapValue.fields || {})) o[k] = value(x);
    return o;
  }
  return undefined;
}
function fields(doc) {
  return value({ mapValue: { fields: doc.fields || {} } });
}

// ---------- Firebase Cloud Messaging ----------
async function send(access, projectId, message) {
  const r = await fetch(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${access}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ message }),
  });
  return r.ok ? 1 : 0;
}
