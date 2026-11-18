# AÏCHA SERVICES — Guide de configuration (version complète)

> Votre satisfaction est notre engagement

## 1. Après l'installation de la nouvelle version

1. **Règles Firestore** : copier le contenu de `firestore.rules` dans
   Firebase → Firestore → Rules → **Publish**.
2. **Créer les boutiques** : Gestion → Boutiques → « Nouvelle boutique »
   (nom, code de 3 lettres comme DJD, localité, adresse, téléphone,
   WhatsApp, horaires, frais de livraison).
3. Les clients choisissent leur boutique à la prochaine ouverture
   (et peuvent en changer dans Profil).

## 2. Responsables et agents

1. La personne installe l'application et **crée son compte** avec son numéro.
2. Gestion → Équipe → « Ajouter un membre » → taper son numéro → Chercher.
3. Choisir la boutique, le rôle (**Responsable** ou **Agent**) et, pour un
   agent, ses permissions → Enregistrer.
4. Elle ferme et rouvre l'application : l'onglet **Gestion** de sa boutique
   apparaît.

Un responsable peut ensuite ajouter lui-même ses agents.

| Fonction | Super Admin | Responsable | Agent |
|---|---|---|---|
| Voir les commandes | toutes | sa boutique | sa boutique |
| Répondre aux clients | oui | oui | oui |
| Modifier les statuts | oui | oui | selon permission |
| Fixer un prix (devis) | oui | oui | selon permission |
| Gérer le catalogue | oui | sa boutique | selon permission |
| Publier des nouveautés | oui | sa boutique | selon permission |
| Voir les clients | oui | oui | selon permission |
| Créer des agents | oui | oui | non |
| Créer une boutique / un responsable | oui | non | non |
| Paramètres généraux | oui | non | non |

Ces droits sont **vérifiés par Firebase** (règles de sécurité), pas
seulement par l'application.

## 3. Envoi de fichiers

Aucune configuration : les fichiers (photos, PDF, Word… jusqu'à 15 Mo) sont
enregistrés directement dans Firebase (collection `blobs`, découpés en
morceaux). Le quota gratuit de Firebase est de 1 Go de données au total.
Pour les fichiers plus lourds, le client utilise WhatsApp.

## 4. Notifications push — Cloudflare (gratuit, sans carte)

**A. Clé Firebase**
Firebase → ⚙️ Paramètres du projet → **Comptes de service** →
**Générer une nouvelle clé privée** → un fichier `.json` est téléchargé.

**B. Serveur Cloudflare**
1. Créer un compte sur **dash.cloudflare.com** (gratuit).
2. **Workers & Pages** → **Create** → **Create Worker** → nom
   `aicha-notify` → **Deploy**.
3. **Edit code** : tout effacer, coller le contenu de `cloudflare/worker.js`
   → **Deploy**.
4. **Settings** → **Variables and Secrets** → **Add** :
   - `SERVICE_ACCOUNT` (type **Secret**) : tout le contenu du fichier `.json`
   - `SUPER_UIDS` (type Text) : `JJj2RolSbmVlWc3n4qT6NvAhxZ63`
   → **Deploy**.
5. Copier l'adresse du worker (`https://aicha-notify.<nom>.workers.dev`).

**C. Dans l'application**
Gestion → **Paramètres** → « Adresse du serveur » → coller l'adresse →
Enregistrer. Puis fermer et rouvrir l'application (accepter les
notifications).

### Notifications envoyées

| Événement | Qui reçoit |
|---|---|
| Nouvelle commande | équipe de la boutique + Super Admin |
| Nouveau message d'un client | équipe de la boutique + Super Admin |
| Réponse de l'équipe | le client (si « Messages » activé) |
| Changement de statut, devis prêt | le client (si « Commandes » activé) |
| Nouveauté / promotion / annonce | clients des boutiques choisies (si « Nouveautés » activé) |

Toucher la notification ouvre directement la commande, la discussion ou
le service concerné.

## 5. Données Firestore

| Collection | Contenu |
|---|---|
| `shops` | boutiques |
| `staff` | responsables et agents (rôle, boutique, permissions) |
| `users` | clients (boutique choisie, préférences, jetons de notification) |
| `catalog` | services (`shopId` = boutique ou `all`) |
| `orders` | commandes (`shopId`, numéro AS-DJD-00125) |
| `counters` | compteurs des numéros de commande |
| `conversations` + `messages` | discussions (générales et par commande) |
| `files` | liste des fichiers envoyés |
| `blobs` | contenu des fichiers (morceaux) |
| `promotions` | nouveautés et offres (`shops` = `all` ou liste) |
| `notifications` | historique des notifications envoyées |
| `settings/shop` | paramètres généraux, Cloudinary, adresse du serveur |
