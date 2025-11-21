# @starforge/api

API minimal pour StarForge (Express + Supabase).

But:
- Expose des routes utiles pour dashboard et bot Discord.
- Authentification via:
  - Supabase JWT (user)
  - clé interne x-api-key (API_SERVER_KEY) pour services/bot

Développement:
1. Copier .env.example -> .env et remplir les valeurs.
2. pnpm install
3. pnpm run dev  # lance l'API
4. pnpm run worker # lance le worker (séparément)

Important:
- NE PAS committer .env avec des secrets.
- Pour production, utiliser SUPABASE_SERVICE_KEY (service_role) côté serveur uniquement.
