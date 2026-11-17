# AICHA SERVICES MARKET 🖨️ — application de commande

Application Android pour **AICHA SERVICES MARKET** (imprimerie et formation).
Les clients commandent leurs impressions **en joignant leur fichier**,
s'inscrivent aux **formations**, et choisissent **livraison** ou **retrait en
boutique**. Ils paient en **espèces**, par **Orange Money**, **Moov Money** ou
**carte bancaire** (via CinetPay).

Vous, le patron, gérez tout dans la même appli (onglet **Gestion**).

Tout se fait **depuis un téléphone** : GitHub compile l'APK pour vous.

---

## Ce que fait l'appli

**Clients**
- Catalogue : Impression / Formation / Autres services, avec recherche
- Envoi du fichier à imprimer (PDF, image, Word… 25 Mo max)
- Précisions (format, papier, couleur…) ou noms des participants
- Prix fixe **ou « sur devis »** : vous fixez le prix final dans l'appli
- Livraison (avec frais) ou retrait en boutique
- Suivi en direct : Nouvelle → Confirmée → En cours → Prête → Livrée
- Bouton WhatsApp et appel vers la boutique

**Patron (onglet Gestion)**
- **Commandes** : filtres (à traiter, devis à faire…), ouverture des
  fichiers clients, fixer le prix d'un devis, changer le statut, appeler ou
  envoyer un WhatsApp au client en un clic
- **Catalogue** : ajouter / modifier / masquer vos services et formations
  (photo, prix, unité, dates, places)
- **Réglages** : téléphone, WhatsApp, adresse, horaires, frais de livraison

---

## Étape 1 — Créer le projet Firebase (≈10 min)

1. <https://console.firebase.google.com> → **Ajouter un projet**.
2. **Authentication** → Commencer → activez **E-mail/Mot de passe**.
3. **Firestore Database** → Créer → région Europe → mode production.
4. **Passez au forfait Blaze** (⚙️ → Utilisation et facturation). Carte
   bancaire demandée, mais l'usage reste **gratuit** dans les quotas.
   Nécessaire pour les fichiers (Storage) et les paiements en ligne.
5. **Storage** → Commencer.
6. ⚙️ **Paramètres du projet** → **Ajouter une application** → Android.
   Nom du package : `ml.aichaservices.aicha_services`.
   Téléchargez `google-services.json` : il contient les valeurs de l'étape 3.

## Étape 2 — Mettre le code sur GitHub

Créez un dépôt sur <https://github.com> et poussez-y ce dossier
(Claude peut le faire pour vous si GitHub est connecté).

## Étape 3 — Ajouter les secrets GitHub

Dépôt → **Settings → Secrets and variables → Actions → New repository secret**

| Secret | Dans `google-services.json` |
|---|---|
| `FIREBASE_API_KEY` | `api_key` → `current_key` |
| `FIREBASE_APP_ID` | `client_info` → `mobilesdk_app_id` |
| `FIREBASE_SENDER_ID` | `project_info` → `project_number` |
| `FIREBASE_PROJECT_ID` | `project_info` → `project_id` |
| `FIREBASE_STORAGE_BUCKET` | `project_info` → `storage_bucket` |

## Étape 4 — Obtenir l'APK 🎉

Onglet **Actions** → « Construire l'APK » → **Run workflow**.
Après ~6 min : ouvrez l'exécution → **Artifacts** → `aicha-services-apk`.
Décompressez et installez `app-release.apk`.

Chaque modification poussée sur `main` recompile l'APK automatiquement.

## Étape 5 — Publier les règles de sécurité (obligatoire)

- Contenu de `firestore.rules` → **Firestore → Règles → Publier**
- Contenu de `storage.rules` → **Storage → Règles → Publier**

## Étape 6 — Devenir « patron » dans l'appli

1. Installez l'APK et **créez votre compte** comme un client.
2. Console Firebase → **Authentication** → copiez votre **UID**.
3. **Firestore** → **Commencer une collection** → nom : `admins` →
   ID du document : **votre UID** → champ `role` = `patron` → Enregistrer.
4. Rouvrez l'appli : l'onglet **Gestion** apparaît.
5. Dans **Gestion → Réglages**, remplissez téléphone, WhatsApp, adresse,
   horaires et frais de livraison. Puis ajoutez vos services dans
   **Catalogue**.

Vous pouvez ajouter un employé de la même façon (un document par UID).

## Étape 7 — Paiements en ligne (facultatif au début)

Sans cette étape, le **paiement en espèces fonctionne déjà**.

1. Compte marchand sur <https://cinetpay.com> → récupérez **API Key** et
   **Site ID**. Vérifiez dans votre tableau de bord quels opérateurs sont
   actifs pour le Mali.
2. Secrets GitHub : `CINETPAY_APIKEY`, `CINETPAY_SITE_ID`.
3. Google Cloud Console → IAM → Comptes de service → compte
   `firebase-adminsdk…` → rôles **Éditeur** et **Utilisateur du compte de
   service** → Clés → Ajouter une clé JSON. Collez tout le JSON dans le
   secret `FIREBASE_SERVICE_ACCOUNT`.
4. **Actions** → « Déployer Firebase » → **Run workflow**.

---

## Sécurité

- Les clés CinetPay restent sur le serveur, jamais dans l'appli.
- Le montant payé est **recalculé côté serveur** (vrais prix du catalogue,
  vrais frais de livraison) ou correspond au **prix fixé par vous** pour un
  devis. Un client ne peut pas modifier ce prix.
- Seul le serveur peut marquer une commande « payée », après vérification
  auprès de CinetPay.
- Seul le patron voit toutes les commandes et les fichiers des clients.

## Personnaliser

- Nom, slogan, couleurs : `lib/config.dart`
- Logo : `assets/logo.png` ; icône de l'appli : `assets/icon.png` et `assets/icon_foreground.png`
- Types de services : `itemTypes` dans `lib/config.dart`

## Idées pour la suite

- Notifications push (nouvelle commande, commande prête)
- Facture / reçu PDF
- Attestation de formation
- Mise en ligne sur le Google Play Store
