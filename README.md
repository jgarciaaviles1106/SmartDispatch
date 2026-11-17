# SmartDispatch — Gestión Logística con Arquitectura Redux en SwiftUI

Aplicación móvil nativa desarrollada en **SwiftUI** para iOS bajo el patrón **Redux / Unidirectional Data Flow (UDF)**, integrada con **Firebase Authentication** y **Cloud Firestore** en tiempo real.

## Información Académica
* **Estudiante:** Julio César García Avilés (`29-0402-2022`)
* **Institución:** Universidad Tecnológica de El Salvador (UTEC)
* **Asignatura:** ETPS4 — Técnicas y Estándares de Programación / Desarrollo de Aplicaciones Móviles
* **Entorno:** macOS Monterey 12.6.1 · Xcode 14.2 · Swift 5.7.2

## Arquitectura Implementada (Redux / UDF)
1. **State (`AppState`):** Única fuente de la verdad inmutable desde las vistas (`usuarioId`, `envios`, `filtroEstado`, `historialAcciones`).
2. **Actions (`AppAction`):** Intenciones explícitas de usuario y sistema (`iniciarSesion`, `registrarUsuario`, `crearEnvio`, `avanzarEstadoEnvio`, `eliminarEnvio`, `cambiarFiltro`).
3. **Reducer (`appReducer`):** Función pura que recibe el estado actual y una acción para producir el nuevo estado de forma predecible.
4. **Store & Middleware (`AppStore`):** Orquestador del flujo unidireccional que ejecuta efectos secundarios asíncronos contra Firebase Auth y Cloud Firestore (`addSnapshotListener`).
5. **Inspector Redux en Vivo:** Monitor integrado en la interfaz que registra cada acción despachada y la mutación resultante del estado en tiempo real.

## Estructura del Proyecto
* `SmartDispatchApp.swift`: Punto de entrada `@main`, inicialización de `FirebaseApp` e inyección de `@StateObject var store = AppStore()`.
* `ReduxCore/`: Definición de modelos de dominio (`Envio`, `EstadoEnvio`), `AppState`, `AppAction`, `appReducer` y `AppStore`.
* `Views/`: Vistas declarativas (`RootView`, `AuthView`, `DashboardDespachoView`, `FilaEnvioView`, `NuevoEnvioSheet`, `InspectorReduxView`).
* `FirebaseLinker.xcconfig`: Configuración de enlazado (`-force_load`) para resolver símbolos estáticos de `GoogleUtilities` en Xcode 14.2.
