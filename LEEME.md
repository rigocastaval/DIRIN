# DIRIN · publicar en línea y dejarlo seguro

Esta carpeta es el sitio completo. No hay que instalar nada ni compilar.

---

## Paso 1 · Preparar la base de datos (una sola vez)

En tu proyecto de Supabase → **SQL Editor** → **New query**, pega y ejecuta
**en este orden**:

1. `supabase-setup.sql`  → crea las tablas.
2. `supabase-seguridad.sql` → cierra los accesos.

Después, en Supabase → **Authentication → Users → Add user**, crea tu propio
usuario (marca *Auto Confirm User*). Luego vuelve al SQL Editor y ejecuta,
cambiando el correo por el tuyo:

    update public.perfiles set rol = 'admin', activo = true
    where correo = 'tucorreo@universidad.mx';

Si la línea dice "0 rows", primero entra una vez a DIRIN con ese correo
(te dirá que no estás autorizado, pero deja creado el perfil) y repite el update.

---

## Paso 2 · Subir el sitio

**Netlify Drop** (gratis, sin conocimientos técnicos):

1. Entra a https://app.netlify.com/drop
2. Arrastra **esta carpeta completa** a la ventana.
3. Te da una dirección tipo `https://algo.netlify.app`. En
   *Site configuration → Change site name* puedes ponerle `dirin-medicina`.
4. Para actualizar después: pestaña *Deploys* → *Deploy manually* → arrastra otra vez.

También sirven Vercel o GitHub Pages; el procedimiento es equivalente.

---

## Paso 3 · Amarrar la dirección al proyecto de Supabase

Supabase → **Authentication → URL Configuration**: pon la dirección de tu sitio
en *Site URL* y agrégala en *Redirect URLs*. Así ningún otro sitio puede usar
tu base de datos para iniciar sesión.

---

## Cómo queda la seguridad

**Nadie sin sesión ve nada.** La liga puede ser pública: sin correo y contraseña
válidos no se puede leer ni un dato. Las tablas están protegidas con RLS y el rol
de visitante (`anon`) quedó sin permisos.

**Una cuenta nueva nace sin acceso.** Aunque alguien lograra registrarse, su
cuenta queda con rol *pendiente* y desactivada: al intentar entrar recibe
"tu cuenta está en espera de autorización" y la sesión se cierra sola.

**Sólo el administrador reparte permisos.** Nadie puede darse a sí mismo el rol
de admin: la base de datos lo rechaza. Desde *Administración de usuarios* tú
cambias el rol de cada persona y la autorizas o desactivas con un botón.

**Cada rol escribe sólo lo suyo.** Padrón, grupos y reingreso: administración,
dirección y control escolar. Carga horaria: administración y dirección.
Los demás roles pueden consultar, no modificar. Esto se cumple en el servidor,
no sólo en la pantalla: no se puede evadir desde el navegador.

**Queda registro.** La tabla `bitacora_cuentas` guarda cada cambio de rol o de
estado, con la fecha y quién lo hizo.

### Recomendaciones para cerrar todavía más

- **Cierra el registro público**: Supabase → *Authentication → Providers → Email*
  → desactiva *Enable Sign-ups*. Con esto sólo tú creas cuentas. Nota: al hacerlo,
  el botón "Crear cuenta" dentro de DIRIN deja de funcionar y las cuentas se dan
  de alta desde Supabase (*Add user*) y luego se autorizan en DIRIN.
- **Limita el dominio de correo**: en `supabase-seguridad.sql`, sección 7,
  quita los comentarios y pon tu dominio. Así sólo se aceptan correos
  institucionales.
- **Oculta el modo de demostración** cuando ya esté en producción: en el panel de
  ajustes de DIRIN, desactiva *permitirDemo*.
- Contraseñas de al menos 10 caracteres y una por persona; nunca una cuenta
  compartida, porque la bitácora dejaría de servir.
- Al salir alguien de la institución: entra a *Administración de usuarios* y
  presiona *Desactivar*. Pierde el acceso al instante.

---

## Instituciones (agregado después)

Si vas a manejar varias instituciones, ejecuta también `supabase-instituciones.sql`
en el SQL Editor, DESPUÉS de los otros dos. Luego, para dejar tu cuenta como
administrador supremo (cambia el correo):

    update public.perfiles set rol = 'super', activo = true
    where correo = 'tucorreo@universidad.mx';

Cómo se usa:

1. Entra a DIRIN → Sistema → **Instituciones** → crea la primera. Todo lo que ya
   estaba capturado (cuentas, reingreso, padrón, horarios) queda a su nombre.
2. En **Identidad institucional** cárgale nombre, colores, logo, membrete y sus
   programas académicos. El sistema adopta esos colores de inmediato.
3. Crea un **Administrador de institución** en Usuarios y permisos. Esa persona
   podrá dar de alta cuentas y repartir permisos, pero sólo dentro de su
   institución: no ve las demás.
4. Al crear una cuenta se le pueden marcar uno o varios programas académicos
   (es opcional). Con programas asignados, esa persona sólo ve los datos de
   esos programas; sin ninguno, ve todo lo de su institución.
5. El administrador supremo ve todas las instituciones y puede entrar a
   cualquiera con el botón «Entrar», para dar apoyo remoto.
