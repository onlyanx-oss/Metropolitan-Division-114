# Web de la Metropolitan Division (LSPD) · versión con base de datos

Web estática (`index.html`) + base de datos de cuentas en Supabase.
Las cuentas se guardan en la base de datos y **solo los administradores pueden cambiar los rangos**.

## Archivos
- `index.html` — la web completa (logos y fotos incrustados).
- `supabase/schema.sql` — crea la base de datos y sus reglas de seguridad.
- `supabase/password_reset.sql` — añade el restablecimiento de contraseña con código.
- `vercel.json` — configuración opcional para Vercel.
- `README.md` — estas instrucciones.

## 1. Crear la base de datos (Supabase, plan gratuito)
1. Entra en https://supabase.com, crea una cuenta y pulsa "New project". Guarda la contraseña de la base de datos.
2. Authentication > (Sign In / Providers) > Email: **desactiva "Confirm email"**. Las cuentas usan un correo ficticio (`usuario@metropolitan-division.app`), así que no se pueden confirmar por correo.
3. SQL Editor > New query: pega todo `supabase/schema.sql` (antes cambia `METRO114` si quieres otro código) y pulsa Run.
4. Project Settings > API (o el botón "Connect"): copia la **Project URL** y la clave **anon / public**. No uses nunca la `service_role`.

## 1b. Restablecer contraseñas con código
Ejecuta también `supabase/password_reset.sql` en el SQL Editor (después de `schema.sql`).
- La comandancia entra en Zona miembros > **Cuentas** y pulsa **Generar código** en la fila del usuario. Aparece un código tipo `ABCD-EFGH` (vale 1 hora, un solo uso, se bloquea tras 5 intentos fallidos).
- Se lo dan a esa persona, que en Acceso miembros usa **¿Olvidaste la contraseña?**: usuario, código y nueva contraseña.
- Un Comandante o Subcomandante solo puede generar códigos para usuarios de **rango inferior** al suyo y que no sean administradores. Los administradores pueden para cualquiera (así se recupera la cuenta de un Comandante).
- Al cambiar la contraseña se cierran las sesiones abiertas de esa cuenta.

## 2. Conectar la web
1. Abre `index.html` con un editor de texto y busca `SUPABASE_URL`.
2. Sustituye `PEGA_AQUI_LA_URL_DE_TU_PROYECTO` y `PEGA_AQUI_LA_CLAVE_ANON` por tus dos valores. Guarda.

## 3. Publicar en Vercel
Igual que antes: sube `index.html` y `vercel.json` a un repositorio de GitHub e impórtalo en https://vercel.com/new?teamSlug=metropolitan-division con "Framework Preset: Other", sin Build Command ni Output Directory. Cada cambio que subas a GitHub se republica solo. (También vale `vercel --prod` desde la terminal.)

## 4. Primer administrador
1. En la web publicada, entra en "Acceso miembros" y regístrate con el código de la División.
2. En Supabase > SQL Editor ejecuta (con tu usuario en minúsculas):
   `update public.profiles set is_admin = true where username = 'tu_usuario';`
3. Cierra sesión y vuelve a entrar. En Zona miembros > **Cuentas** verás todas las cuentas y podrás cambiar rangos (empieza por poner el tuyo como Comandante).
4. Para hacer administrador a otra persona, repite el paso 2 con su usuario. Eso solo se puede hacer desde Supabase, no desde la web.

## Si dice que la base de datos no está configurada o no conecta
En "Acceso miembros" hay ahora una línea de estado que dice exactamente qué falla:
- **"faltan SUPABASE_URL y SUPABASE_KEY"**: la web que ves no tiene tus valores. Comprueba que los pegaste entre las comillas en `index.html`, que subiste el archivo a GitHub y que Vercel terminó el despliegue (pestaña Deployments). Recarga con Ctrl+F5.
- **"La URL de Supabase no es correcta"**: usa la *Project URL* (`https://xxxx.supabase.co`), no la dirección del panel ni una con `/rest/v1/`.
- **"No se pudo cargar la librería"**: recarga sin caché o desactiva el bloqueador de anuncios.
- **"falta la tabla profiles"**: no se ejecutó `schema.sql` en el SQL Editor.
- **"La clave no es válida"**: usa la clave *anon / public*, completa y sin espacios.
- **"Base de datos conectada"**: todo bien; si falla el registro, es el código de la División, el usuario repetido o "Confirm email" sin desactivar.
Para más detalle, abre la consola del navegador (F12) y busca líneas que empiecen por `[DB]`.

## Cómo funciona la seguridad
- Cada cuenta nueva empieza como **Aspirante**; el rango solo lo cambia un administrador.
- Los rangos Comandante y Subcomandante dan acceso a la pestaña Cuentas (solo lectura) y a las funciones de comandancia de la web.
- El código de registro se comprueba en la base de datos, no en la página, y nadie puede leerlo desde la web.
- Las reglas (RLS) impiden que un usuario se suba el rango llamando directamente a la base de datos.

## Limitaciones
- Solo las **cuentas y los rangos** están en la base de datos. Informes, capacitaciones, uniformes, vehículos, fotos del SWAT y estado del reclutamiento siguen guardándose en el navegador de cada persona. Se pueden pasar también a la base de datos.
- Si alguien olvida la contraseña: la comandancia le genera un código (ver arriba). Si hiciera falta, también puedes borrar su usuario en Supabase > Authentication > Users para que se registre de nuevo.
- Si al registrarse aparece un error de correo no válido, cambia `EMAIL_DOMAIN` en `index.html` por un dominio válido.
- El contenido de la zona de miembros sigue estando dentro del código de la página: no pongas información confidencial.
