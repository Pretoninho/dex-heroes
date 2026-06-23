# ☁️ Dex Heroes — Backend (Phase A : comptes + sauvegarde cloud)

Architecture : le jeu reste un **site statique** (GitHub Pages) ; il appelle
**Supabase** (Postgres + Auth) directement depuis le navigateur. Aucun serveur à
héberger. La sécurité repose sur la **Row-Level Security** (RLS) : chaque joueur
n'accède qu'à sa propre ligne.

> Tant que les clés ne sont pas renseignées, **le jeu marche en local**
> (`localStorage`) comme avant — `cloud.js` se désactive tout seul.

## Mise en place (≈ 5 min)

1. **Crée un projet** sur [supabase.com](https://supabase.com) (gratuit).
2. **Schéma** : ouvre *SQL Editor → New query*, colle le contenu de
   [`schema.sql`](./schema.sql) et clique **Run**.
3. **Auth e-mail** : *Authentication → Providers → Email* activé.
   - Pour tester sans friction : *Authentication → Settings* → désactive
     « Confirm email » (sinon il faut cliquer le lien reçu par mail avant de se
     connecter).
4. **Clés** : *Project Settings → API* → copie **Project URL** et la clé
   **anon public**.
5. Ouvre **`cloud.js`** (à la racine) et remplace en haut :
   ```js
   var SUPABASE_URL = "https://TON-PROJET.supabase.co";
   var SUPABASE_ANON_KEY = "TA_CLE_ANON_PUBLIC";
   ```
6. Recharge le jeu : un onglet **☁️** apparaît dans le menu → *Créer un compte* /
   *Connexion*. Ta sauvegarde se synchronise alors automatiquement.

## Comment ça marche
- À la connexion, on charge la sauvegarde cloud (**la plus récente gagne**, via
  `lastSeen`). S'il n'y en a pas, on y pousse la partie locale.
- Ensuite, chaque sauvegarde (auto toutes les 15 s, ou au bouton) est aussi
  **poussée dans le cloud** (throttlée ~8 s).

## ⚠️ Anti-triche (à savoir)
La sauvegarde cloud est **pratique mais pas infalsifiable** : l'état vient du
client. C'est acceptable pour du *save*. Pour le **classement** (Phase B) puis le
**marché de gemmes** (Phase C), les opérations sensibles devront être **validées
côté serveur** (Edge Functions + transactions). Voir `docs/heroes.md` / le GDD.

## Roadmap backend
- **Phase A — comptes + cloud save** *(ce scaffold)*.
- **Phase B — classement** (table `scores`, déjà esquissée en commentaire dans
  `schema.sql`).
- **Phase C — marché in-game** (gemmes ↔ cash, **zéro argent réel**), transactions
  autoritatives serveur.
