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

**Kao WeTransfer, ali bez skidanja i ponovnog slanja**: štamparija dobije link (mejlom ili
Viberom), vidi veličinu paketa i rok, i jednim klikom preuzme ZIP sa **originalima u punoj
rezoluciji** direktno sa servera (koji ih čita sa vašeg Drive-a). Vaš internet se ne troši.
Ime svakog fajla počinje brojem kopija (`2x_DSC_4120.jpg`); ako je u paketu više klijenata,
svako ima svoj folder; uz to ide `SPISAK.txt`.

> **Zašto ne pravi WeTransfer?** WeTransfer je ugasio javni API za programere (nema više
> ključeva), pa nijedna aplikacija ne može automatski da šalje preko njega. Ručno slanje bi
> značilo da prvo skinete sve fotografije pa ih ponovo otpremite — upravo ono što ovaj link
> izbegava.

---

## Za klijente (namerno maksimalno jednostavno)

- Bez prijave, bez lozinke — samo link.
- Dodir na **krug** na fotografiji = izabrana (postaje **zelena sa kvačicom**).
- Dodir na samu fotografiju = prikaz preko celog ekrana, prevlačenje za sledeću,
  i veliko dugme **„Izaberi ovu fotografiju”**.
- Sve se **čuva samo od sebe** (može da zatvori stranicu i nastavi kasnije).
- Svi dobijaju isti format (**13x18**, menja se u Podešavanjima) — klijent bira samo
  **broj primeraka** (veliki − / + odmah ispod izabrane fotografije).
- Veliko zeleno dugme **„Dalje”** → provera → ime → **„Pošalji”**.
- Dugme **„Pomoć”** sa objašnjenjima običnim jezikom; uputstvo u 3 koraka stoji na vrhu.
- Može da izmeni izbor dok vi ne pošaljete na štampu.
- Na istom linku može da bira više ljudi (npr. gosti na venčanju) — svako ima svoj izbor.

## Za vas (administrator)

- **Pregled**: nove porudžbine, ko trenutno bira, zauzeće Drive-a, „Pošalji sve štampariji”.
- **Projekti**: naslovna fotografija, tajni link, QR kod, „Pošalji klijentu”,
  otpremanje prevlačenjem (na računaru) ili izborom iz galerije (na telefonu),
  brisanje, naslovna, redosled po vremenu snimanja, broj klijenata koji su izabrali sliku (♥).
- **Pravila po projektu**: najviše N fotografija, rok za izbor, status
  (otvoren / samo pregled / skriven).
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

### 2. Postavljanje na vaš domen (bez kucanja komandi)

Aplikaciju ne pokrećete kod sebe — ona radi na **serveru**, na **vašem domenu**
(npr. `https://foto.vasdomen.rs`). GitHub je sam izgradi i postavi posle svake izmene.

**a) Server (VPS).** Aplikaciji treba mali Linux server (Ubuntu 24.04, 2 GB RAM je dovoljno):
- [Hetzner Cloud](https://www.hetzner.com/cloud) CX22 (~4 €/mes, 20 TB saobraćaja), ili
- DigitalOcean — sa **GitHub Student Pack-om** dobijate 200 $ kredita.

Pri pravljenju servera izaberite **Ubuntu 24.04** i zapamtite **IP adresu** i **root lozinku**
(ili dodajte svoj SSH ključ).

> Ako vam je domen/sajt na običnom hostingu (cPanel), sajt ostaje tamo — samo dodajete
> poddomen (npr. `foto.`) koji pokazuje na novi server. Običan PHP hosting ne može da pokreće
> ovu aplikaciju.

**b) DNS.** Kod registra domena (gde ste kupili domen) dodajte **A zapis**:

| Tip | Ime | Vrednost |
|---|---|---|
| A | `foto` | IP adresa servera |

**c) GitHub secrets.** U repozitorijumu: **Settings → Secrets and variables → Actions →
New repository secret**, dodajte:

| Ime | Vrednost |
|---|---|
| `DEPLOY_HOST` | IP adresa servera |
| `DEPLOY_PASSWORD` | root lozinka servera *(ili `DEPLOY_SSH_KEY` — privatni SSH ključ)* |
| `DOMAIN` | `foto.vasdomen.rs` |
| `GOOGLE_CLIENT_ID` | iz koraka 1 |
| `GOOGLE_CLIENT_SECRET` | iz koraka 1 |
| `DRIVE_EMAIL` | *(opciono)* nalog sa 5 TB, ako nije `minehost43@gmail.com` |
| `SMTP_HOST`, `SMTP_USER`, `SMTP_PASSWORD` | *(opciono)* za mejl štampariji jednim dodirom |
| `DEPLOY_USER` | *(opciono)* korisnik na serveru, podrazumevano `root` |

**d) Pokretanje.** GitHub → **Actions → Deploy → Run workflow → Run workflow**.
Za ~10 minuta aplikacija radi na `https://foto.vasdomen.rs` — HTTPS sertifikat se dobija
automatski. Posle toga se svaka izmena na grani `main` postavlja sama (a ručno pokretanje
uvek radi). Ako nešto nije podešeno, Actions jasno napiše šta nedostaje.

Šta deploy radi na serveru: instalira Docker (prvi put), postavlja aplikaciju u `/opt/fotograf`,
pravi tajni ključ za šifrovanje **na samom serveru** (nikad ne napušta server) i pokreće
aplikaciju + Caddy (HTTPS). Podaci i baza ostaju između verzija.

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
