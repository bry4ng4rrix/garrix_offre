# Garrix Offre — application Flutter

Application **Android** et **Linux** de Garrix Offre : offres d'emploi et missions freelance
triées par score de matching, préparation et suivi des candidatures, CV, alertes en temps réel.
Interface **noire (#000000), minimaliste, pensée d'abord pour le téléphone** ; sur un grand écran
(Linux), la barre de navigation du bas devient un rail latéral et le contenu reste centré.

---

## 1. Démarrage rapide

Prérequis : Flutter 3.44 (stable), et selon la cible :
- **Linux** : `clang cmake ninja pkg-config gtk3 libsecret` (Arch : `sudo pacman -S clang cmake ninja pkgconf gtk3 libsecret`) ;
- **Android** : Android SDK + JDK 17 ou plus (fourni par Android Studio).

```bash
cd mobile
flutter pub get
flutter run -d linux          # application de bureau
flutter run -d <id-du-telephone>   # voir `flutter devices` (débogage USB activé)
```

Au premier lancement, l'écran de connexion utilise le serveur de production
`http://185.215.167.79:8000`. Pour un backend local : touchez **Serveur** en bas de l'écran de
connexion, saisissez `http://localhost:8000` (Linux) ou `http://<IP-du-PC>:8000` (téléphone sur le
même Wi-Fi), puis **Tester** et **Enregistrer**.

Compte de démonstration du backend local (`make seed-dev` dans `backend/`) :
`demo@example.com` / `DemoPassw0rd!`.

## 2. Construire les applications

```bash
flutter build apk --release        # build/app/outputs/flutter-apk/app-release.apk
flutter build linux --release      # build/linux/x64/release/bundle/ (lancer ./garrix_offre)
```

Installer l'APK sur un téléphone branché : `adb install -r build/app/outputs/flutter-apk/app-release.apk`
(ou copiez le fichier sur le téléphone et ouvrez-le).

### Signature Android

`android/key.properties` (jamais commité) pointe vers la clé de release
`~/.android-keys/garrix-offre-release.jks`. **Sauvegardez ce fichier** : sans lui, une nouvelle
version ne pourra pas s'installer par-dessus l'ancienne (il faudrait désinstaller l'application).
Sans `key.properties`, la release est signée avec la clé de debug.

```properties
storePassword=...
keyPassword=...
keyAlias=garrix
storeFile=/home/<vous>/.android-keys/garrix-offre-release.jks
```

## 3. Pas de CI pour l'application

Les builds Android et Linux se font **manuellement en local** (section 2) : aucun workflow GitHub
Actions ni déploiement sur le VPS pour `mobile/`. Avant chaque build, lancez `flutter analyze` et
`flutter test` (section 5).

## 4. Architecture

```
lib/
├── main.dart, app.dart           # démarrage, thème, localisation fr_FR, routeur
├── core/
│   ├── config/                   # URL du serveur (modifiable, persistée)
│   ├── network/                  # ApiClient (Dio) : enveloppe {success, data}, erreurs en français,
│   │                             #   renouvellement automatique du token sur 401, pagination
│   ├── auth/                     # session (tokens : Keystore Android / trousseau Linux), utilisateur
│   ├── realtime/                 # WebSocket /api/v1/ws (reconnexion, token expiré -> refresh)
│   ├── router/                   # go_router : 5 onglets + pages plein écran, garde admin
│   ├── models/                   # énumérations de l'API (libellés FR, couleurs), référentiels
│   ├── theme/                    # palette noir pur, typographie Inter, composants Material 3
│   ├── widgets/                  # design system : cartes, pastilles, score, listes paginées, formulaires
│   └── utils/                    # formatage (dates, salaires, tailles), lecture JSON
└── features/
    ├── auth/                     # connexion, inscription, choix du serveur
    ├── dashboard/                # accueil : chiffres du jour, meilleures offres, candidatures
    ├── jobs/                     # recherche, filtres, détail, matching, analyse IA, ajout manuel
    ├── applications/             # candidatures : préparation, génération, validation, suivi
    ├── documents/                # CV et documents : envoi, téléchargement, CV principal
    ├── notifications/            # alertes temps réel, préférences Telegram / email
    ├── profile/                  # profil, photo, compétences, expériences, préférences, matching
    ├── settings/                 # compte, serveur, mot de passe, IA, à propos
    └── admin/                    # utilisateurs, sources, collectes, système, audit, référentiels
```

Chaque fonctionnalité suit la même organisation : `data/` (modèles `fromJson`/`toJson` et
repository qui appelle l'API), pages `*_page.dart`, `widgets/` réutilisables. L'état est géré avec
**Riverpod 3** (`FutureProvider`, `Notifier`), la navigation avec **go_router**.

### Règles importantes reprises du backend

- Une candidature n'est **jamais envoyée sans confirmation explicite** : le bouton « Valider
  l'envoi » ouvre un récapitulatif avec une case à cocher, puis appelle `POST /applications/{id}/submit`
  avec `confirm: true`.
- Les transitions de statut proposées sont celles autorisées par le backend
  (`ApplicationStatus.allowedTransitions`, identique à `backend/app/modules/applications/rules.py`).
- L'espace **Administration** n'apparaît que pour un compte administrateur (et le routeur bloque
  l'accès aux autres).

### Design

- Fond `#000000`, surfaces `#0A0A0A` → `#1F1F1F`, bordures fines, texte blanc / gris, accent blanc ;
  couleurs sémantiques (vert, ambre, rouge) réservées aux statuts et aux scores.
- Police **Inter** (incluse, licence OFL), icônes Material arrondies.
- Composants communs dans `lib/core/widgets/` : `AppCard`, `Pill`, `ScoreRing`, `StatTile`,
  `PagedListView`, `AppTextField`, `EmptyState`, `showToast`, `confirmDialog`...

## 5. Qualité

```bash
flutter analyze     # aucune remarque attendue
flutter test        # tests unitaires (core + modèles de chaque fonctionnalité)
```

## 6. Sécurité

- Tokens stockés dans le Keystore Android / le trousseau Linux (libsecret). Si aucun trousseau
  n'est disponible sous Linux, repli sur les préférences locales de l'utilisateur.
- `android:usesCleartextTraffic="true"` : le serveur est en HTTP tant qu'il n'a pas de nom de
  domaine avec HTTPS. **À retirer dès que l'API passe en HTTPS** (mots de passe et tokens circulent
  sinon en clair sur le réseau).
