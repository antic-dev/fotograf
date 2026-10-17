# 📸 Fotograf

Web aplikacija za fotografe: otpremite fotografije na **svoj Google Drive**, pošaljite klijentu
**tajni link**, klijent na telefonu izabere šta želi da odštampa, a vi jednim dodirom
pošaljete štampariji link sa **originalima u punoj rezoluciji**.

- **Flutter Web** aplikacija (lepa i jednostavna na telefonu, za klijente i za vas)
- **Dart server** (bez Firebase-a) sa SQLite bazom
- **Google Drive** kao skladište — svaki projekat je poseban folder

---

## Kako izgleda tok

```
 VI (administrator)                    KLIJENT (bez naloga)                ŠTAMPARIJA
 ──────────────────                    ────────────────────                ──────────
 1. Novi projekat ──► folder na Drive-u
 2. Otpremite fotografije (originali)
 3. "Pošalji klijentu" (Viber/WhatsApp) ──► otvara link
                                          dodirne krug = izabrano ✓
                                          "Dalje" → broj primeraka/veličina
                                          upiše ime → "Pošalji fotografu"
 4. Vidite porudžbinu ◄──────────────────┘
 5. "Pošalji štampariji" ─────────────────────────────────────────────► otvara link
                                                                        "Preuzmi sve (ZIP)"
                                                                        originali, po veličinama
```

**Vaš internet se ne troši pri slanju štampariji**: štamparija preuzima originale direktno
sa servera (koji ih čita sa vašeg Drive-a). Ne morate ništa da skidate i ponovo šaljete,
kao kod WeTransfer-a. ZIP je raspoređen u foldere po veličini i papiru, a ime svakog fajla
počinje brojem kopija (`2x_Ana Petrović_DSC_4120.jpg`), uz `SPISAK.txt`.

---

## Za klijente (namerno maksimalno jednostavno)

- Bez prijave, bez lozinke — samo link.
- Dodir na **krug** na fotografiji = izabrana (postaje **zelena sa kvačicom**).
- Dodir na samu fotografiju = prikaz preko celog ekrana, prevlačenje za sledeću,
  i veliko dugme **„Izaberi ovu fotografiju”**.
- Sve se **čuva samo od sebe** (može da zatvori stranicu i nastavi kasnije).
- Veliko zeleno dugme **„Dalje”** → broj primeraka, veličina, papir → ime → **„Pošalji”**.
- Dugme **„Pomoć”** sa objašnjenjima običnim jezikom; uputstvo u 3 koraka stoji na vrhu.
- Može da izmeni izbor dok vi ne pošaljete na štampu.
- Na istom linku može da bira više ljudi (npr. gosti na venčanju) — svako ima svoj izbor.

## Za vas (administrator)

- **Pregled**: nove porudžbine, ko trenutno bira, zauzeće Drive-a, „Pošalji sve štampariji”.
- **Projekti**: naslovna fotografija, tajni link, QR kod, „Pošalji klijentu”,
  otpremanje prevlačenjem (na računaru) ili izborom iz galerije (na telefonu),
  brisanje, naslovna, redosled po vremenu snimanja, broj klijenata koji su izabrali sliku (♥).
- **Pravila po projektu**: najviše N fotografija, rok za izbor, veličine (10x15, 13x18...),
  vrste papira, status (otvoren / samo pregled / skriven).
- **Porudžbine**: nove su unapred označene → jedan dodir „Pošalji štampariji”.
- **Štamparija**: istorija linkova, koliko puta je otvoren, opoziv u svakom trenutku.
- Otpremanje radi u pozadini, 2 fotografije paralelno (dobro za sporiji internet),
  sa dugmetom „Ponovi” za neuspele.

---

## 🔒 Bezbednost

| Pretnja | Zaštita |
|---|---|
| Neko drugi kao administrator | Samo `minehost43@gmail.com`; Google ID token se **kriptografski proverava na serveru** (RS256, izdavalac, aud, rok, verifikovan mejl) + jednokratni **nonce** protiv ponovne upotrebe tokena |
| Krađa sesije | Nasumični 256-bitni token u `HttpOnly; Secure; SameSite=Strict` kolačiću (`__Host-` prefiks); u bazi se čuva samo SHA-256 heš; ističe posle 12 h (ili 4 h neaktivnosti); „Odjavi sve uređaje” |
| Pogađanje linkova | 192-bitni nasumični tokeni; u bazi samo heš; ograničen broj pokušaja po IP adresi |
| Pristup tuđem projektu | Server za **svaku** sliku proverava da pripada projektu tog linka; link jednog projekta ne otvara nijedan drugi |
| Krađa fotografija od strane klijenta | Klijenti vide **samo smanjen pregled (1280 px) sa dijagonalnim vodenim žigom preko cele slike**, na nasumičnim pozicijama (teško uklonjiv AI alatima); slike se crtaju na canvas (nema „Sačuvaj sliku”), desni klik je isključen, server odbija direktno otvaranje slike u pregledaču, štampa stranice je prazna. Originali nikad ne idu klijentu |
| CSRF / clickjacking | Provera porekla + obavezno `X-Fotograf` zaglavlje; `frame-ancestors 'none'`; bez CORS-a |
| XSS / ubacivanje koda | Stroga `Content-Security-Policy` bez inline skripti; svi SQL upiti su parametrizovani |
| Zlonamerni fajlovi | Format se prepoznaje po sadržaju (ne po imenu); zaštita od „image bomb” fajlova; EXIF (GPS) se uklanja iz pregleda |
| Pristup vašem Drive-u | Dozvola `drive.file` — aplikacija vidi **samo fajlove koje je sama napravila**, ostatak Drive-a joj je nevidljiv. Refresh token je šifrovan (AES-256-GCM); povezivanje koristi PKCE |
| Link štamparije | Ističe (7–60 dana), može se opozvati, beleži broj otvaranja |
| Praćenje | Dnevnik aktivnosti (prijave, neuspeli pokušaji, slanja...) u Podešavanjima |

> Iskreno: snimak ekrana (screenshot) ne može da spreči nijedan sajt. Zato je zaštita
> u tome što klijent nikada ne dobije original — screenshot daje sliku sa žigom i niske
> rezolucije, nedovoljne za kvalitetnu štampu.

---

## 🚀 Postavljanje (jednom)

### 1. Google Cloud (≈10 minuta)

1. Otvorite <https://console.cloud.google.com> (nalogom `minehost43@gmail.com`) → **New project** → „Fotograf”.
2. **APIs & Services → Library** → potražite **Google Drive API** → **Enable**.
3. **APIs & Services → OAuth consent screen** (Google Auth Platform):
   - User type: **External**, naziv aplikacije „Fotograf”, vaš mejl za podršku.
   - **Data access / Scopes**: dodajte `openid`, `.../auth/userinfo.email` i `.../auth/drive.file`.
   - **Audience → Publish app** (prebacite u **In production**).
     ⚠️ Važno: u režimu „Testing” Google gasi pristup Drive-u posle 7 dana.
     `drive.file` ne zahteva Google verifikaciju.
4. **APIs & Services → Credentials → Create credentials → OAuth client ID**:
   - Application type: **Web application**
   - **Authorized JavaScript origins**: `https://foto.vasdomen.rs`
   - **Authorized redirect URIs**: `https://foto.vasdomen.rs/api/admin/drive/callback`
   - Kopirajte **Client ID** i **Client secret**.

### 2. Server

Bilo koji Linux VPS sa Docker-om (npr. Hetzner ~4 €/mes, ili kredit iz GitHub Student
Pack-a za DigitalOcean/Azure). Domen (GitHub Student Pack daje besplatan `.me`/`.tech`)
usmerite **A zapisom** na IP servera.

```bash
git clone https://github.com/antic-dev/fotograf.git && cd fotograf
cp .env.example .env
openssl rand -base64 32        # nalepite rezultat kao APP_SECRET u .env
nano .env                      # DOMAIN, PUBLIC_URL, GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET
docker compose up -d --build
```

Caddy automatski dobija HTTPS sertifikat. Gotovo!

### 3. Prvo pokretanje

1. Otvorite `https://foto.vasdomen.rs/admin` → **Sign in with Google**.
2. **Podešavanja → Poveži Google Drive** → dozvolite pristup.
   Na Drive-u se pojavljuje folder **Fotograf**.
3. Upišite naziv studija (koristi se i za žig) i mejl štamparije.

> Ako je vaših 5 TB na **drugom** Google nalogu (npr. studentskom), upišite ga kao
> `DRIVE_EMAIL` u `.env`. Prijava u aplikaciju ostaje samo za `ADMIN_EMAIL`.
> (Fakultetski Google Workspace nalozi ponekad imaju zabranu za aplikacije trećih
> strana — tada se obratite administratoru fakulteta ili koristite lični nalog.)

### Opciono: mejl štampariji jednim dodirom

Bez ovoga aplikacija otvara vašu mejl aplikaciju sa već napisanom porukom.
Za slanje direktno iz aplikacije: Google nalog → **Bezbednost → Verifikacija u 2 koraka →
Lozinke za aplikacije**, pa u `.env`:

```
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=minehost43@gmail.com
SMTP_PASSWORD=xxxx xxxx xxxx xxxx
```

### Rezervna kopija

Originali su na vašem Google Drive-u. Baza (projekti, porudžbine, linkovi) je u Docker
volumenu `fotograf-data` — povremeno je kopirajte:

```bash
docker compose cp app:/data/fotograf.db ./backup-$(date +%F).db
```

---

## 🧪 Demo bez Google naloga

Da vidite celu aplikaciju lokalno, sa izmišljenim fotografijama:

```bash
cd app && flutter build web --release --no-web-resources-cdn
cd ../server && dart run tool/demo_server.dart
```

U konzoli se ispišu link za klijenta i za administratora.

## 🛠️ Razvoj

```
app/      Flutter web (lib/client — klijenti, lib/admin — administrator, lib/print — štamparija)
server/   Dart server (lib/src/routes — API, drive.dart, images.dart — žig, zip_stream.dart)
deploy/   Caddy (HTTPS)
```

```bash
cd server && dart test          # testovi bezbednosti i celog toka
cd app && flutter analyze && flutter test
```
