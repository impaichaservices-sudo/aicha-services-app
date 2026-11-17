/**
 * Paiement en ligne AICHA SERVICES MARKET via CinetPay (Orange Money, Moov Money, carte).
 *
 * - initPayment   : appelée par l'appli. Recalcule le montant côté serveur
 *                   (à partir des vrais prix en base), crée la transaction
 *                   CinetPay et renvoie l'URL de paiement.
 * - cinetpayNotify: appelée par CinetPay après le paiement. Vérifie le statut
 *                   auprès de CinetPay puis marque les commandes "payées".
 * - cinetpayReturn: page affichée au client à la fin du paiement.
 *
 * Variables (fichier functions/.env, généré par GitHub Actions) :
 *   CINETPAY_APIKEY, CINETPAY_SITE_ID
 */
const { onCall, onRequest, HttpsError } = require('firebase-functions/v2/https');
const { setGlobalOptions } = require('firebase-functions/v2');
const logger = require('firebase-functions/logger');
const admin = require('firebase-admin');

admin.initializeApp();
const db = admin.firestore();
const REGION = 'europe-west1';
setGlobalOptions({ region: REGION, maxInstances: 5 });

const CINETPAY_URL = 'https://api-checkout.cinetpay.com/v2/payment';

function baseUrl() {
  const project = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT;
  return `https://${REGION}-${project}.cloudfunctions.net`;
}

function normalizePhone(phone) {
  const digits = String(phone || '').replace(/[^\d+]/g, '');
  if (digits.startsWith('+')) return digits;
  if (digits.startsWith('00')) return `+${digits.slice(2)}`;
  return `+223${digits}`;
}

async function cinetpay(path, body) {
  const res = await fetch(CINETPAY_URL + path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      apikey: process.env.CINETPAY_APIKEY,
      site_id: process.env.CINETPAY_SITE_ID,
      ...body,
    }),
  });
  return res.json();
}

exports.initPayment = onCall(async (req) => {
  if (!req.auth) throw new HttpsError('unauthenticated', 'Connexion requise.');
  const { orderIds, channel } = req.data || {};
  if (!Array.isArray(orderIds) || orderIds.length === 0 || orderIds.length > 20) {
    throw new HttpsError('invalid-argument', 'Commandes invalides.');
  }
  const channels = ['MOBILE_MONEY', 'CREDIT_CARD'];
  const chosen = channels.includes(channel) ? channel : 'ALL';

  const refs = orderIds.map((id) => db.collection('orders').doc(String(id)));
  const snaps = await db.getAll(...refs);

  const settings = (await db.collection('settings').doc('shop').get()).data() || {};
  const deliveryFee = Number(settings.deliveryFee) || 0;

  let total = 0;
  let customer = null;
  for (const snap of snaps) {
    if (!snap.exists) throw new HttpsError('not-found', 'Commande introuvable.');
    const o = snap.data();
    if (o.buyerId !== req.auth.uid) {
      throw new HttpsError('permission-denied', 'Cette commande ne vous appartient pas.');
    }
    if (o.paymentStatus === 'paye') {
      throw new HttpsError('failed-precondition', 'Commande déjà payée.');
    }
    if (o.status === 'annulee') {
      throw new HttpsError('failed-precondition', 'Commande annulée.');
    }

    if (typeof o.quotedTotal === 'number') {
      // Prix final fixé par le patron (seul lui peut écrire ce champ).
      total += o.quotedTotal;
    } else {
      if (o.quoteNeeded) {
        throw new HttpsError('failed-precondition',
          'Le prix final de votre commande n\'est pas encore fixé.');
      }
      // Montant recalculé avec les VRAIS prix du catalogue.
      for (const item of o.items || []) {
        const p = await db.collection('catalog').doc(item.itemId).get();
        if (!p.exists || !(Number(p.data().price) > 0)) {
          throw new HttpsError('failed-precondition', `Service indisponible : ${item.name}`);
        }
        const qty = Math.max(1, Math.floor(Number(item.qty) || 1));
        total += Number(p.data().price) * qty;
      }
      if (o.delivery === 'livraison') total += deliveryFee;
    }
    customer = o;
  }

  if (!Number.isInteger(total) || total <= 0 || total % 5 !== 0) {
    throw new HttpsError('failed-precondition', 'Montant invalide (multiple de 5 requis).');
  }

  const transactionId = `AICHA${Date.now()}${Math.floor(Math.random() * 1000)}`;
  const [firstName, ...rest] = String(customer.buyerName || 'Client').split(' ');
  const json = await cinetpay('', {
    transaction_id: transactionId,
    amount: total,
    currency: 'XOF',
    description: `Commande AICHA SERVICES MARKET`,
    channels: chosen,
    lang: 'FR',
    notify_url: `${baseUrl()}/cinetpayNotify`,
    return_url: `${baseUrl()}/cinetpayReturn`,
    metadata: transactionId,
    customer_id: req.auth.uid,
    customer_name: firstName || 'Client',
    customer_surname: rest.join(' ') || firstName || 'Client',
    // Les clients se connectent par numéro : pas de vraie adresse e-mail.
    customer_email: 'client@aichaservices.ml',
    customer_phone_number: normalizePhone(customer.phone),
    customer_address: customer.address || 'Bamako',
    customer_city: customer.city || 'Bamako',
    customer_country: 'ML',
    customer_state: 'ML',
    customer_zip_code: '00000',
  });

  if (json.code !== '201' || !json.data || !json.data.payment_url) {
    logger.error('CinetPay init error', json);
    throw new HttpsError('internal', json.description || json.message || 'Erreur CinetPay.');
  }

  await db.collection('payments').doc(transactionId).set({
    uid: req.auth.uid,
    orderIds,
    amount: total,
    channel: chosen,
    status: 'en_attente',
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return { paymentUrl: json.data.payment_url, transactionId };
});

exports.cinetpayNotify = onRequest(async (req, res) => {
  const txId = (req.body && req.body.cpm_trans_id) || req.query.cpm_trans_id;
  // CinetPay peut tester l'URL sans identifiant : on répond simplement OK.
  if (!txId) {
    res.status(200).send('OK');
    return;
  }

  const payRef = db.collection('payments').doc(String(txId));
  const pay = await payRef.get();
  if (!pay.exists) {
    res.status(404).send('Transaction inconnue');
    return;
  }

  // On ne croit jamais la notification sur parole : on demande à CinetPay.
  const check = await cinetpay('/check', { transaction_id: String(txId) });
  const status = check && check.data && check.data.status;
  const paidAmount = Number(check && check.data && check.data.amount);

  let paymentStatus = 'en_attente';
  if (status === 'ACCEPTED') {
    paymentStatus = paidAmount >= pay.data().amount ? 'paye' : 'echec';
  } else if (status === 'REFUSED' || status === 'CANCELED') {
    paymentStatus = 'echec';
  }

  if (paymentStatus !== pay.data().status) {
    const batch = db.batch();
    batch.update(payRef, {
      status: paymentStatus,
      cinetpay: check.data || null,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    for (const id of pay.data().orderIds) {
      batch.update(db.collection('orders').doc(id), {
        paymentStatus,
        paymentRef: String(txId),
      });
    }
    await batch.commit();
    logger.info(`Paiement ${txId} -> ${paymentStatus}`);
  }
  res.status(200).send('OK');
});

exports.cinetpayReturn = onRequest((req, res) => {
  res.set('Content-Type', 'text/html; charset=utf-8').send(`<!DOCTYPE html>
<html lang="fr"><head><meta name="viewport" content="width=device-width,initial-scale=1">
<title>AICHA SERVICES - Paiement</title></head>
<body style="font-family:sans-serif;text-align:center;padding:48px 24px">
<h2>Merci !</h2>
<p>Votre paiement est en cours de vérification.</p>
<p>Retournez dans l'application <b>AICHA SERVICES MARKET</b> : le statut de votre commande
se mettra à jour automatiquement.</p>
</body></html>`);
});
