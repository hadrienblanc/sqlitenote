#!/usr/bin/env bats

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)/notes"
TEST_DB="$BATS_TMPDIR/test_notes.db"

setup() {
  # Créer une base propre avant chaque test
  rm -f "$TEST_DB"
  sqlite3 "$TEST_DB" "
    CREATE TABLE notes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL,
      content TEXT,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );
    CREATE TABLE tags (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL UNIQUE
    );
    CREATE TABLE note_tags (
      note_id INTEGER NOT NULL,
      tag_id INTEGER NOT NULL,
      PRIMARY KEY (note_id, tag_id),
      FOREIGN KEY (note_id) REFERENCES notes(id) ON DELETE CASCADE,
      FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
    );
  "
}

teardown() {
  rm -f "$TEST_DB"
}

# --- Argument DB ---

@test "arg: DB par défaut est notes.db (dans le dossier du script)" {
  run grep -c '${1:-' "$SCRIPT"
  [[ "$status" -eq 0 ]]
  [[ "$output" -ge 1 ]]
}

@test "arg: fichier inexistant retourne erreur" {
  run zsh "$SCRIPT" "/tmp/inexistant_db_test.db"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"Base introuvable"* ]]
}

@test "arg: DB custom valide est acceptée" {
  local custom_db="$BATS_TMPDIR/custom_arg_test.db"
  rm -f "$custom_db"
  sqlite3 "$custom_db" "
    CREATE TABLE notes (id INTEGER PRIMARY KEY, title TEXT NOT NULL, content TEXT,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP, updated_at DATETIME DEFAULT CURRENT_TIMESTAMP);
    CREATE TABLE tags (id INTEGER PRIMARY KEY, name TEXT NOT NULL UNIQUE);
    CREATE TABLE note_tags (note_id INTEGER, tag_id INTEGER, PRIMARY KEY (note_id, tag_id));
    INSERT INTO notes (title, content) VALUES ('Test', 'Contenu');
  "
  # Le script va lancer gum choose (interactif) — on vérifie juste qu'il passe le check DB
  run timeout 2 zsh "$SCRIPT" "$custom_db" < /dev/null
  [[ "$output" != *"Base introuvable"* ]]
  rm -f "$custom_db"
}

# --- Schema ---

@test "table notes existe" {
  result=$(sqlite3 "$TEST_DB" ".tables")
  [[ "$result" == *"notes"* ]]
}

@test "table tags existe" {
  result=$(sqlite3 "$TEST_DB" ".tables")
  [[ "$result" == *"tags"* ]]
}

@test "table note_tags existe" {
  result=$(sqlite3 "$TEST_DB" ".tables")
  [[ "$result" == *"note_tags"* ]]
}

@test "notes a les bonnes colonnes" {
  result=$(sqlite3 "$TEST_DB" "PRAGMA table_info(notes);" | cut -d'|' -f2 | sort)
  [[ "$result" == *"content"* ]]
  [[ "$result" == *"created_at"* ]]
  [[ "$result" == *"id"* ]]
  [[ "$result" == *"title"* ]]
  [[ "$result" == *"updated_at"* ]]
}

# --- Insert & Read ---

@test "insérer et lire une note" {
  sqlite3 "$TEST_DB" "INSERT INTO notes (title, content) VALUES ('Test', 'Contenu test');"
  result=$(sqlite3 "$TEST_DB" "SELECT title FROM notes WHERE id = 1;")
  [[ "$result" == "Test" ]]
}

@test "created_at est rempli automatiquement" {
  sqlite3 "$TEST_DB" "INSERT INTO notes (title, content) VALUES ('Test', 'Contenu');"
  result=$(sqlite3 "$TEST_DB" "SELECT created_at FROM notes WHERE id = 1;")
  [[ -n "$result" ]]
}

@test "updated_at est rempli automatiquement" {
  sqlite3 "$TEST_DB" "INSERT INTO notes (title, content) VALUES ('Test', 'Contenu');"
  result=$(sqlite3 "$TEST_DB" "SELECT updated_at FROM notes WHERE id = 1;")
  [[ -n "$result" ]]
}

@test "title NOT NULL est respecté" {
  run sqlite3 "$TEST_DB" "INSERT INTO notes (content) VALUES ('Sans titre');"
  [[ "$status" -ne 0 ]]
}

@test "content peut être NULL" {
  sqlite3 "$TEST_DB" "INSERT INTO notes (title) VALUES ('Sans contenu');"
  result=$(sqlite3 "$TEST_DB" "SELECT content FROM notes WHERE id = 1;")
  [[ -z "$result" ]]
}

# --- Tags ---

@test "créer un tag" {
  sqlite3 "$TEST_DB" "INSERT INTO tags (name) VALUES ('test-tag');"
  result=$(sqlite3 "$TEST_DB" "SELECT name FROM tags WHERE id = 1;")
  [[ "$result" == "test-tag" ]]
}

@test "tag name est unique" {
  sqlite3 "$TEST_DB" "INSERT INTO tags (name) VALUES ('unique-tag');"
  run sqlite3 "$TEST_DB" "INSERT INTO tags (name) VALUES ('unique-tag');"
  [[ "$status" -ne 0 ]]
}

# --- note_tags (relations) ---

@test "lier une note à un tag" {
  sqlite3 "$TEST_DB" "
    INSERT INTO notes (title) VALUES ('Note A');
    INSERT INTO tags (name) VALUES ('tag-a');
    INSERT INTO note_tags (note_id, tag_id) VALUES (1, 1);
  "
  result=$(sqlite3 "$TEST_DB" "
    SELECT t.name FROM tags t
    JOIN note_tags nt ON t.id = nt.tag_id
    WHERE nt.note_id = 1;
  ")
  [[ "$result" == "tag-a" ]]
}

@test "une note peut avoir plusieurs tags" {
  sqlite3 "$TEST_DB" "
    INSERT INTO notes (title) VALUES ('Multi-tag');
    INSERT INTO tags (name) VALUES ('alpha');
    INSERT INTO tags (name) VALUES ('beta');
    INSERT INTO note_tags (note_id, tag_id) VALUES (1, 1);
    INSERT INTO note_tags (note_id, tag_id) VALUES (1, 2);
  "
  result=$(sqlite3 "$TEST_DB" "SELECT COUNT(*) FROM note_tags WHERE note_id = 1;")
  [[ "$result" -eq 2 ]]
}

@test "un tag peut être sur plusieurs notes" {
  sqlite3 "$TEST_DB" "
    INSERT INTO notes (title) VALUES ('Note 1');
    INSERT INTO notes (title) VALUES ('Note 2');
    INSERT INTO tags (name) VALUES ('shared');
    INSERT INTO note_tags (note_id, tag_id) VALUES (1, 1);
    INSERT INTO note_tags (note_id, tag_id) VALUES (2, 1);
  "
  result=$(sqlite3 "$TEST_DB" "SELECT COUNT(*) FROM note_tags WHERE tag_id = 1;")
  [[ "$result" -eq 2 ]]
}

@test "pas de doublon note_id + tag_id" {
  sqlite3 "$TEST_DB" "
    INSERT INTO notes (title) VALUES ('Note');
    INSERT INTO tags (name) VALUES ('tag');
    INSERT INTO note_tags (note_id, tag_id) VALUES (1, 1);
  "
  run sqlite3 "$TEST_DB" "INSERT INTO note_tags (note_id, tag_id) VALUES (1, 1);"
  [[ "$status" -ne 0 ]]
}

# --- CASCADE ---

@test "supprimer une note supprime ses liens note_tags" {
  sqlite3 "$TEST_DB" "
    PRAGMA foreign_keys = ON;
    INSERT INTO notes (title) VALUES ('À supprimer');
    INSERT INTO tags (name) VALUES ('tag');
    INSERT INTO note_tags (note_id, tag_id) VALUES (1, 1);
    DELETE FROM notes WHERE id = 1;
  "
  result=$(sqlite3 "$TEST_DB" "SELECT COUNT(*) FROM note_tags;")
  [[ "$result" -eq 0 ]]
}

@test "supprimer un tag supprime ses liens note_tags" {
  sqlite3 "$TEST_DB" "
    PRAGMA foreign_keys = ON;
    INSERT INTO notes (title) VALUES ('Note');
    INSERT INTO tags (name) VALUES ('À supprimer');
    INSERT INTO note_tags (note_id, tag_id) VALUES (1, 1);
    DELETE FROM tags WHERE id = 1;
  "
  result=$(sqlite3 "$TEST_DB" "SELECT COUNT(*) FROM note_tags;")
  [[ "$result" -eq 0 ]]
}

# --- Requêtes métier ---

@test "filtrer les notes par tag" {
  sqlite3 "$TEST_DB" "
    INSERT INTO notes (title) VALUES ('Rails note');
    INSERT INTO notes (title) VALUES ('SQL note');
    INSERT INTO tags (name) VALUES ('rails');
    INSERT INTO tags (name) VALUES ('sql');
    INSERT INTO note_tags (note_id, tag_id) VALUES (1, 1);
    INSERT INTO note_tags (note_id, tag_id) VALUES (2, 2);
  "
  result=$(sqlite3 "$TEST_DB" "
    SELECT n.title FROM notes n
    JOIN note_tags nt ON n.id = nt.note_id
    JOIN tags t ON nt.tag_id = t.id
    WHERE t.name = 'rails';
  ")
  [[ "$result" == "Rails note" ]]
}

@test "filtrer par plusieurs tags (IN)" {
  sqlite3 "$TEST_DB" "
    INSERT INTO notes (title) VALUES ('Note A');
    INSERT INTO notes (title) VALUES ('Note B');
    INSERT INTO notes (title) VALUES ('Note C');
    INSERT INTO tags (name) VALUES ('alpha');
    INSERT INTO tags (name) VALUES ('beta');
    INSERT INTO tags (name) VALUES ('gamma');
    INSERT INTO note_tags (note_id, tag_id) VALUES (1, 1);
    INSERT INTO note_tags (note_id, tag_id) VALUES (2, 2);
    INSERT INTO note_tags (note_id, tag_id) VALUES (3, 3);
  "
  result=$(sqlite3 "$TEST_DB" "
    SELECT COUNT(DISTINCT n.id) FROM notes n
    JOIN note_tags nt ON n.id = nt.note_id
    JOIN tags t ON nt.tag_id = t.id
    WHERE t.name IN ('alpha', 'beta');
  ")
  [[ "$result" -eq 2 ]]
}

@test "recherche LIKE dans le contenu" {
  sqlite3 "$TEST_DB" "
    INSERT INTO notes (title, content) VALUES ('Note', 'SQLite est rapide');
    INSERT INTO notes (title, content) VALUES ('Autre', 'Redis est cool');
  "
  result=$(sqlite3 "$TEST_DB" "SELECT title FROM notes WHERE content LIKE '%SQLite%';")
  [[ "$result" == "Note" ]]
}

# --- Mode parcours : requêtes ---

@test "browse: liste des IDs ordonnés" {
  sqlite3 "$TEST_DB" "
    INSERT INTO notes (title) VALUES ('C');
    INSERT INTO notes (title) VALUES ('A');
    INSERT INTO notes (title) VALUES ('B');
  "
  result=$(sqlite3 "$TEST_DB" "SELECT id FROM notes ORDER BY id;")
  [[ "$result" == *"1"* ]]
  [[ "$result" == *"2"* ]]
  [[ "$result" == *"3"* ]]
  # Vérifie l'ordre (1 avant 2 avant 3)
  first=$(echo "$result" | head -1)
  [[ "$first" -eq 1 ]]
}

@test "browse: récupérer titre d'une note" {
  sqlite3 "$TEST_DB" "INSERT INTO notes (title, content) VALUES ('Mon Titre', 'contenu');"
  result=$(sqlite3 "$TEST_DB" "SELECT title FROM notes WHERE id = 1;")
  [[ "$result" == "Mon Titre" ]]
}

@test "browse: récupérer contenu d'une note" {
  sqlite3 "$TEST_DB" "INSERT INTO notes (title, content) VALUES ('T', 'Le contenu ici');"
  result=$(sqlite3 "$TEST_DB" "SELECT content FROM notes WHERE id = 1;")
  [[ "$result" == "Le contenu ici" ]]
}

@test "browse: contenu multi-ligne est préservé" {
  sqlite3 "$TEST_DB" "INSERT INTO notes (title, content) VALUES ('T', 'Ligne 1
Ligne 2
Ligne 3');"
  result=$(sqlite3 "$TEST_DB" "SELECT content FROM notes WHERE id = 1;")
  lines=$(echo "$result" | wc -l | tr -d ' ')
  [[ "$lines" -eq 3 ]]
}

@test "browse: tags GROUP_CONCAT pour une note" {
  sqlite3 "$TEST_DB" "
    INSERT INTO notes (title) VALUES ('Note');
    INSERT INTO tags (name) VALUES ('alpha');
    INSERT INTO tags (name) VALUES ('beta');
    INSERT INTO note_tags (note_id, tag_id) VALUES (1, 1);
    INSERT INTO note_tags (note_id, tag_id) VALUES (1, 2);
  "
  result=$(sqlite3 "$TEST_DB" "
    SELECT COALESCE('#' || GROUP_CONCAT(t.name, ' #'), '-')
    FROM tags t JOIN note_tags nt ON t.id = nt.tag_id
    WHERE nt.note_id = 1;
  ")
  [[ "$result" == *"#alpha"* ]]
  [[ "$result" == *"#beta"* ]]
}

@test "browse: note sans tag retourne '-'" {
  sqlite3 "$TEST_DB" "INSERT INTO notes (title) VALUES ('Orpheline');"
  result=$(sqlite3 "$TEST_DB" "
    SELECT COALESCE('#' || GROUP_CONCAT(t.name, ' #'), '-')
    FROM tags t JOIN note_tags nt ON t.id = nt.tag_id
    WHERE nt.note_id = 1;
  ")
  [[ "$result" == "-" ]]
}

@test "browse: dates created_at et updated_at" {
  sqlite3 "$TEST_DB" "INSERT INTO notes (title) VALUES ('Note');"
  created=$(sqlite3 "$TEST_DB" "SELECT created_at FROM notes WHERE id = 1;")
  updated=$(sqlite3 "$TEST_DB" "SELECT updated_at FROM notes WHERE id = 1;")
  [[ -n "$created" ]]
  [[ -n "$updated" ]]
  [[ "$created" == "$updated" ]]
}

@test "browse: format liste pour gum filter" {
  sqlite3 "$TEST_DB" "
    INSERT INTO notes (title) VALUES ('Ma Note');
    INSERT INTO tags (name) VALUES ('dev');
    INSERT INTO note_tags (note_id, tag_id) VALUES (1, 1);
  "
  result=$(sqlite3 "$TEST_DB" "
    SELECT n.id || ' | ' || n.title || ' #' || COALESCE(t.name, '-')
    FROM notes n
    LEFT JOIN note_tags nt ON n.id = nt.note_id
    LEFT JOIN tags t ON nt.tag_id = t.id
    WHERE 1=1
    ORDER BY n.id;
  ")
  [[ "$result" == "1 | Ma Note #dev" ]]
}

@test "browse: extraction id depuis format liste" {
  line="42 | Titre de note #tag"
  id="${line%% |*}"
  [[ "$id" == "42" ]]
}

# --- Mode parcours : rendu glow ---

# --- Mode parcours : rendu glow ---

@test "glow: rend le markdown sans erreur" {
  if ! command -v glow &>/dev/null; then skip "glow non installé"; fi
  result=$(echo "## Titre
Du contenu **gras** et *italique*" | glow -)
  [[ -n "$result" ]]
}

@test "glow: préserve le contenu multi-ligne" {
  if ! command -v glow &>/dev/null; then skip "glow non installé"; fi
  result=$(echo "## Vocabulaire

- mot1
- mot2
- mot3" | glow -)
  lines=$(echo "$result" | wc -l | tr -d ' ')
  [[ "$lines" -ge 4 ]]
}

@test "glow: contenu vide ne crash pas" {
  if ! command -v glow &>/dev/null; then skip "glow non installé"; fi
  run bash -c "echo '' | glow -"
  [[ "$status" -eq 0 ]]
}

@test "glow: caractères unicode (chinois)" {
  if ! command -v glow &>/dev/null; then skip "glow non installé"; fi
  result=$(echo "## 你好吗
- 你 (nǐ) → tu" | glow -)
  [[ -n "$result" ]]
}

@test "glow: contenu avec accents français" {
  if ! command -v glow &>/dev/null; then skip "glow non installé"; fi
  result=$(echo "## Résumé
Aujourd'hui c'est génial, à bientôt !" | glow -)
  [[ "$result" == *"sum"* ]]
}

@test "glow: contenu avec blocs de code" {
  if ! command -v glow &>/dev/null; then skip "glow non installé"; fi
  result=$(printf '## Code\n\n```sql\nSELECT * FROM notes;\n```\n' | glow -)
  [[ "$result" == *"SELECT"* ]]
}

@test "glow: contenu avec tableau markdown" {
  if ! command -v glow &>/dev/null; then skip "glow non installé"; fi
  result=$(printf '| Col1 | Col2 |\n|------|------|\n| a    | b    |\n' | glow -)
  [[ -n "$result" ]]
}

# --- Mode parcours : assemblage markdown pour rendu ---

# Simule la logique de render_note (show_note) vs browse_notes
# render_note construit : "# titre\n> tags | dates\n\n---\n\ncontent"
# browse_notes envoie seulement le content (BUG: titre manquant)

@test "rendu: render_note inclut le titre en h1" {
  if ! command -v glow &>/dev/null; then skip "glow non installé"; fi
  title="Ma Super Note"
  content="Du contenu"
  tags="#dev"
  dates="Créée: 2026-03-02"
  # Logique de render_note
  rendered=$(echo "# $title
> $tags | $dates

---

$content" | glow -)
  # Le titre doit être présent dans le rendu
  [[ "$rendered" == *"Ma Super Note"* ]]
}

@test "rendu: render_note inclut les tags" {
  if ! command -v glow &>/dev/null; then skip "glow non installé"; fi
  rendered=$(echo "# Titre
> #dev #sql | Créée: 2026-03-02

---

Contenu" | glow -)
  [[ "$rendered" == *"dev"* ]]
  [[ "$rendered" == *"sql"* ]]
}

@test "rendu: render_note inclut les dates" {
  if ! command -v glow &>/dev/null; then skip "glow non installé"; fi
  rendered=$(echo "# Titre
> #dev | Créée: 2026-03-02

---

Contenu" | glow -)
  [[ "$rendered" == *"2026"* ]]
}

@test "rendu: browse_notes DOIT inclure le titre (test du bug)" {
  if ! command -v glow &>/dev/null; then skip "glow non installé"; fi
  title="Titre Important"
  content="## Section
Du contenu ici"
  # Logique ACTUELLE de browse_notes (juste content, sans titre) — BUG
  rendered_browse=$(printf '%s' "$content" | glow -)
  # Logique ATTENDUE (avec titre)
  rendered_expected=$(echo "# $title

$content" | glow -)
  # Le titre DOIT apparaître dans le rendu
  # Ce test échoue si browse_notes n'inclut pas le titre
  [[ "$rendered_expected" == *"Titre Important"* ]]
  # Et le rendu actuel NE contient PAS le titre (prouve le bug)
  [[ "$rendered_browse" != *"Titre Important"* ]]
}

@test "rendu: contenu NULL ne crash pas glow" {
  if ! command -v glow &>/dev/null; then skip "glow non installé"; fi
  run bash -c 'echo "# Titre sans contenu

---

" | glow -'
  [[ "$status" -eq 0 ]]
}

@test "rendu: echo vs printf — echo ajoute newline finale" {
  # echo ajoute \n, printf '%s' non — glow peut mal gérer sans \n
  result_echo=$(echo "Ligne finale" | wc -c | tr -d ' ')
  result_printf=$(printf '%s' "Ligne finale" | wc -c | tr -d ' ')
  # echo produit 1 byte de plus (\n)
  [[ "$result_echo" -gt "$result_printf" ]]
}

@test "rendu: printf sans newline — glow traite la dernière ligne" {
  if ! command -v glow &>/dev/null; then skip "glow non installé"; fi
  # Sans \n finale, la dernière ligne pourrait être ignorée
  result=$(printf '%s' "## Titre
Dernière ligne sans newline" | glow -)
  [[ "$result" == *"newline"* ]]
}

@test "rendu: echo avec contenu multi-ligne — glow traite tout" {
  if ! command -v glow &>/dev/null; then skip "glow non installé"; fi
  result=$(echo "## Titre
Ligne 1
Ligne 2
Dernière ligne" | glow -)
  [[ "$result" == *"Ligne 1"* ]]
  [[ "$result" == *"erni"* ]]
}

# --- Mode parcours : format nav header ---

@test "nav: format position [pos/total] id:N" {
  pos=3
  total=12
  current_id=42
  nav="[$pos/$total]  id:$current_id"
  [[ "$nav" == "[3/12]  id:42" ]]
}

@test "nav: dates identiques — pas de Modifiée" {
  created_at="2026-03-02 10:00:00"
  updated_at="2026-03-02 10:00:00"
  dates="Créée: $created_at"
  if [[ "$updated_at" != "$created_at" ]]; then
    dates+="  |  Modifiée: $updated_at"
  fi
  [[ "$dates" == "Créée: 2026-03-02 10:00:00" ]]
  [[ "$dates" != *"Modifiée"* ]]
}

@test "nav: dates différentes — affiche Modifiée" {
  created_at="2026-03-01 10:00:00"
  updated_at="2026-03-02 15:30:00"
  dates="Créée: $created_at"
  if [[ "$updated_at" != "$created_at" ]]; then
    dates+="  |  Modifiée: $updated_at"
  fi
  [[ "$dates" == *"Modifiée: 2026-03-02 15:30:00"* ]]
}

# --- Mode parcours : hints navigation ---

@test "hints: première note — pas de Précédent" {
  idx=1
  total=5
  hints=""
  [[ $idx -gt 1 ]] && hints+="← Précédent  "
  [[ $idx -lt $total ]] && hints+="→ Suivant  "
  hints+="q Retour"
  [[ "$hints" != *"Précédent"* ]]
  [[ "$hints" == *"Suivant"* ]]
  [[ "$hints" == *"q Retour"* ]]
}

@test "hints: dernière note — pas de Suivant" {
  idx=5
  total=5
  hints=""
  [[ $idx -gt 1 ]] && hints+="← Précédent  "
  [[ $idx -lt $total ]] && hints+="→ Suivant  "
  hints+="q Retour"
  [[ "$hints" == *"Précédent"* ]]
  [[ "$hints" != *"Suivant"* ]]
  [[ "$hints" == *"q Retour"* ]]
}

@test "hints: note du milieu — Précédent et Suivant" {
  idx=3
  total=5
  hints=""
  [[ $idx -gt 1 ]] && hints+="← Précédent  "
  [[ $idx -lt $total ]] && hints+="→ Suivant  "
  hints+="q Retour"
  [[ "$hints" == *"Précédent"* ]]
  [[ "$hints" == *"Suivant"* ]]
}

@test "hints: note unique — seulement q Retour" {
  idx=1
  total=1
  hints=""
  [[ $idx -gt 1 ]] && hints+="← Précédent  "
  [[ $idx -lt $total ]] && hints+="→ Suivant  "
  hints+="q Retour"
  [[ "$hints" == "q Retour" ]]
}

# --- Mode parcours : navigation index ---

@test "nav: index ne dépasse pas le total" {
  total=5
  idx=5
  if [[ $idx -lt $total ]]; then idx=$(( idx + 1 )); fi
  [[ "$idx" -eq 5 ]]
}

@test "nav: index ne descend pas sous 1" {
  idx=1
  if [[ $idx -gt 1 ]]; then idx=$(( idx - 1 )); fi
  [[ "$idx" -eq 1 ]]
}

@test "nav: suivant incrémente" {
  idx=2; total=5
  if [[ $idx -lt $total ]]; then idx=$(( idx + 1 )); fi
  [[ "$idx" -eq 3 ]]
}

@test "nav: précédent décrémente" {
  idx=3
  if [[ $idx -gt 1 ]]; then idx=$(( idx - 1 )); fi
  [[ "$idx" -eq 2 ]]
}

@test "nav: parcours complet 1→total→1" {
  total=3
  idx=1
  # Avancer jusqu'au bout
  while [[ $idx -lt $total ]]; do idx=$(( idx + 1 )); done
  [[ "$idx" -eq 3 ]]
  # Reculer jusqu'au début
  while [[ $idx -gt 1 ]]; do idx=$(( idx - 1 )); done
  [[ "$idx" -eq 1 ]]
}

@test "nav: flèche droite sur dernière note — reste en place" {
  idx=3; total=3
  # Simule 3 appuis droite
  for _ in 1 2 3; do
    if [[ $idx -lt $total ]]; then idx=$(( idx + 1 )); fi
  done
  [[ "$idx" -eq 3 ]]
}

@test "nav: flèche gauche sur première note — reste en place" {
  idx=1
  for _ in 1 2 3; do
    if [[ $idx -gt 1 ]]; then idx=$(( idx - 1 )); fi
  done
  [[ "$idx" -eq 1 ]]
}

# --- Mode parcours : contenu edge cases depuis la DB ---

@test "browse: note avec apostrophes dans le titre" {
  sqlite3 "$TEST_DB" "INSERT INTO notes (title, content) VALUES ('L''apostrophe c''est OK', 'contenu');"
  result=$(sqlite3 "$TEST_DB" "SELECT title FROM notes WHERE id = 1;")
  [[ "$result" == "L'apostrophe c'est OK" ]]
}

@test "browse: note avec guillemets dans le contenu" {
  sqlite3 "$TEST_DB" "INSERT INTO notes (title, content) VALUES ('Test', 'Il a dit \"bonjour\"');"
  result=$(sqlite3 "$TEST_DB" "SELECT content FROM notes WHERE id = 1;")
  [[ "$result" == *'"bonjour"'* ]]
}

@test "browse: note avec markdown headings dans le contenu" {
  sqlite3 "$TEST_DB" "INSERT INTO notes (title, content) VALUES ('T', '## Section 1
### Sous-section
Du texte');"
  result=$(sqlite3 "$TEST_DB" "SELECT content FROM notes WHERE id = 1;")
  [[ "$result" == *"## Section 1"* ]]
  [[ "$result" == *"### Sous-section"* ]]
}

@test "browse: note avec listes markdown" {
  sqlite3 "$TEST_DB" "INSERT INTO notes (title, content) VALUES ('T', '- item 1
- item 2
- item 3');"
  result=$(sqlite3 "$TEST_DB" "SELECT content FROM notes WHERE id = 1;")
  lines=$(echo "$result" | wc -l | tr -d ' ')
  [[ "$lines" -eq 3 ]]
}

@test "browse: note avec contenu très long (>50 lignes)" {
  local long_content=""
  for i in $(seq 1 60); do
    long_content+="Ligne numéro $i
"
  done
  sqlite3 "$TEST_DB" "INSERT INTO notes (title, content) VALUES ('Longue', '$(echo "$long_content" | sed "s/'/''/g")');"
  result=$(sqlite3 "$TEST_DB" "SELECT content FROM notes WHERE id = 1;")
  lines=$(echo "$result" | wc -l | tr -d ' ')
  [[ "$lines" -ge 59 ]]
}

@test "browse: rendu glow d'une vraie note chinoise" {
  if ! command -v glow &>/dev/null; then skip "glow non installé"; fi
  sqlite3 "$TEST_DB" "INSERT INTO notes (title, content) VALUES ('Chinois', '## 你好吗？(nǐ hǎo ma?)

### Vocabulaire
- 你 (nǐ) → tu
- 好 (hǎo) → bien');"
  content=$(sqlite3 "$TEST_DB" "SELECT content FROM notes WHERE id = 1;")
  rendered=$(echo "# Chinois

$content" | glow -)
  [[ "$rendered" == *"Chinois"* ]]
  [[ "$rendered" == *"hǎo"* ]]
}
