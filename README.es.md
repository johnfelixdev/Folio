# Folio

**Un editor de PDF nativo para macOS que trabaja entero en tu Mac.**

[English](README.md)

Folio es un editor de PDF de escritorio escrito en Swift 6 y SwiftUI. Los
documentos se procesan en local. La app que monta `Scripts/build-app.sh`
funciona en sandbox y se firma sin el permiso de red, así que no puede abrir
conexiones. No tiene telemetría, analíticas ni actualizador. Dónde guardas tus
archivos (por ejemplo, en una carpeta sincronizada con la nube) lo decides tú.

> **Estado: fase 1 de 4, en curso.** Ya se pueden organizar páginas y
> guardar. Anotar, editar texto y los formularios llegan en fases
> posteriores (ver la [hoja de ruta](#hoja-de-ruta)). Por ahora la interfaz
> solo está en castellano.

## Qué hace hoy

- **Abrir, crear y guardar PDF.** La app se apoya en `DocumentGroup` y
  `ReferenceFileDocument`, así que el autoguardado, las versiones, *Revertir*
  y la marca «Editado» de la barra de título los gestiona el propio sistema.
- **Vista de lectura** con una tira de miniaturas. Al elegir una miniatura,
  el lienzo salta a esa página.
- **Mesa de luz.** Una cuadrícula de páginas a pantalla completa. Arrastra una
  o varias páginas para reordenarlas, o suelta otros PDF encima para unirlos
  en el orden en que los soltaste. Las páginas solo se mueven dentro de su
  propio documento.
- **Rotar y borrar** las páginas seleccionadas.
- **Deshacer y rehacer cualquier operación** con el ⌘Z del sistema.
- **PDF con restricciones.** Folio detecta los documentos que se abren sin
  contraseña pero prohíben imprimir, copiar o editar, y puede rehacerlos sin
  esas marcas, conservando el título, el autor y los marcadores. Nunca adivina
  ni rompe una contraseña: un PDF que la pide para *abrirse* sigue cerrado. Usa
  esta función solo con documentos de los que tengas los derechos o que estés
  autorizado a modificar, según lo que permita la ley que te aplique.
- **Inspector** con el número de páginas y el estado de protección.

Dividir y extraer páginas están hechos y probados en el núcleo
(`ExportService`), pero la interfaz todavía no los usa.

## Arquitectura

```
Interfaz SwiftUI   (FolioApp)
        │  emite comandos
        ▼
Documento + deshacer   (FolioDocument, PageCommand)
        │
        ▼
Protocolo PDFEngine ← PDFKitEngine
```

- **Las ediciones del PDF pasan por el protocolo `PDFEngine`.** Fuera del
  motor, solo el lienzo de lectura importa PDFKit, para mostrar el `PDFView`
  del sistema, y un test (`ArchitectureTests`) vigila que siga así. PDFKit no
  sabe editar el texto existente, así que la fase 3 necesitará un segundo motor
  (PDFium o MuPDF), que se conectará a ese protocolo. Hoy el documento y algunos
  comandos aún crean `PDFKitEngine` directamente, así que en la fase 3 también
  habrá que inyectar el motor ahí.
- **Cada edición es un comando que devuelve su propio inverso**, así que
  deshacer repite operaciones en vez de guardar una copia del documento en
  cada paso.
- **Cada página tiene una identidad estable (UUID) que sobrevive a los
  cambios de orden**: mover o rotar una página solo redibuja las miniaturas
  que cambiaron de verdad.
- **Guardar no necesita trabajo en el hilo principal.** El sistema pide los
  bytes del documento en segundo plano mientras el hilo principal espera al
  guardado, así que los bytes se actualizan en el hilo principal tras cada
  cambio y el guardado solo los lee.
- **Insertar páginas es todo o nada.** Todas las páginas se leen antes de
  insertar la primera, y soltar varios archivos se deshace en un solo paso.

## Requisitos

- macOS 26 o posterior
- Herramientas de Swift 6 (Xcode o las Command Line Tools)

Sin dependencias externas.

## Compilar y ejecutar

```bash
swift build
swift test
./Scripts/build-app.sh   # monta build/Folio.app en sandbox y con firma ad hoc
open build/Folio.app
```

Sin `.xcodeproj` ni catálogo de recursos: la app entera se compila con
`swift build` y las Command Line Tools. Xcode puede abrir igualmente
`Package.swift` para las vistas previas y la depuración. Si no existe
`Scripts/icon-source.png`, el guion genera un icono provisional.

## Tests

111 tests en 13 suites, con Swift Testing. Los PDF cifrados y con
restricciones los generan las fixtures con CoreGraphics al correr los tests,
y también se leen con CoreGraphics. Así no hay ficheros PDF en el
repositorio y PDFKit nunca se evalúa a sí mismo.

## Limitaciones conocidas

- Deshacer el borrado de una página la recupera, pero no los marcadores que
  apuntaban a ella.
- Tras borrar o deshacer, la vista de lectura conserva su posición por número
  de página, así que puede mostrar la página de al lado.
- Dividir y extraer todavía no están en la interfaz.
- La interfaz solo está en castellano.

## Hoja de ruta

| Fase | Alcance | Estado |
|---|---|---|
| 1 · Núcleo y páginas | Abrir/guardar, visor, miniaturas, unir, dividir, reordenar, rotar, borrar, extraer, deshacer/rehacer, quitar restricciones de permisos | En curso |
| 2 · Anotar y firmar | Resaltar, subrayar, notas, dibujo, cajas de texto, firma | Prevista |
| 3 · Editar texto e imágenes | Reescribir párrafos respetando fuente y tamaño; mover y reemplazar imágenes | Prevista |
| 4 · Formularios y OCR | Rellenar y aplanar formularios; hacer buscables los escaneos | Prevista |

## Autor

Hecho por **John Felix** · [GitHub](https://github.com/johnfelixdev)

## Licencia

[MIT](LICENSE)
