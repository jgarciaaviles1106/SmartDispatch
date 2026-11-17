import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

// MARK: - 1. MODELOS DE DOMINIO
enum EstadoEnvio: String, CaseIterable, Codable {
    case pendiente = "Pendiente"
    case enRuta = "En Ruta"
    case entregado = "Entregado"
}

struct Envio: Identifiable, Equatable {
    var id: String
    var codigoGuia: String
    var cliente: String
    var destino: String
    var conductor: String
    var estado: EstadoEnvio
    var fechaCreacion: Date
}

struct RegistroAccionRedux: Identifiable, Equatable {
    let id = UUID()
    let marcaTiempo: Date
    let nombreAccion: String
    let resumenCambio: String
}

// MARK: - 2. STATE (Única Fuente de la Verdad - Inmutable desde la Vista)
struct AppState: Equatable {
    var usuarioEmail: String? = nil
    var usuarioId: String? = nil
    var cargandoAuth: Bool = false
    var errorMensaje: String? = nil
    
    var envios: [Envio] = []
    var cargandoEnvios: Bool = false
    var filtroEstado: EstadoEnvio? = nil
    
    // Factor Wow: Historial de acciones Redux en tiempo real
    var historialAcciones: [RegistroAccionRedux] = []
    var mostrarInspectorRedux: Bool = false
    
    var enviosFiltrados: [Envio] {
        guard let filtro = filtroEstado else { return envios }
        return envios.filter { $0.estado == filtro }
    }
}

// MARK: - 3. ACTIONS (Intenciones explícitas del usuario o del sistema)
enum AppAction {
    // Autenticación
    case iniciarSesion(email: String, password: String)
    case registrarUsuario(email: String, password: String)
    case cerrarSesion
    case authCompletada(uid: String, email: String)
    case authFallida(String)
    
    // Gestión de Despachos (CRUD)
    case iniciarEscuchaEnvios
    case enviosActualizados([Envio])
    case crearEnvio(codigoGuia: String, cliente: String, destino: String, conductor: String)
    case avanzarEstadoEnvio(Envio)
    case eliminarEnvio(String)
    case errorOperacion(String)
    
    // UI & Inspector Redux
    case cambiarFiltro(EstadoEnvio?)
    case toggleInspectorRedux
    case limpiarError
    
    var descripcionCorta: String {
        switch self {
        case .iniciarSesion(let email, _): return "AUTH_LOGIN (\(email))"
        case .registrarUsuario(let email, _): return "AUTH_REGISTER (\(email))"
        case .cerrarSesion: return "AUTH_LOGOUT"
        case .authCompletada(_, let email): return "AUTH_SUCCESS (\(email))"
        case .authFallida(let err): return "AUTH_ERROR (\(err))"
        case .iniciarEscuchaEnvios: return "FIRESTORE_SUBSCRIBE"
        case .enviosActualizados(let lista): return "ENVÍOS_SYNC (\(lista.count) docs)"
        case .crearEnvio(let guia, _, _, _): return "CREATE_ENVÍO (\(guia))"
        case .avanzarEstadoEnvio(let envio): return "UPDATE_ESTADO (\(envio.codigoGuia))"
        case .eliminarEnvio(let id): return "DELETE_ENVÍO (\(id.prefix(6)))"
        case .errorOperacion(let msg): return "ERROR_OP (\(msg))"
        case .cambiarFiltro(let estado): return "SET_FILTER (\(estado?.rawValue ?? "Todos"))"
        case .toggleInspectorRedux: return "TOGGLE_REDUX_INSPECTOR"
        case .limpiarError: return "CLEAR_ERROR"
        }
    }
}

// MARK: - 4. REDUCER PURO (Estado Anterior + Acción -> Nuevo Estado)
func appReducer(state: inout AppState, action: AppAction) {
    let resumenAnterior = "Envíos: \(state.envios.count) | Auth: \(state.usuarioEmail ?? "nil")"
    
    switch action {
    case .iniciarSesion, .registrarUsuario:
        state.cargandoAuth = true
        state.errorMensaje = nil
        
    case .authCompletada(let uid, let email):
        state.cargandoAuth = false
        state.usuarioId = uid
        state.usuarioEmail = email
        state.errorMensaje = nil
        
    case .authFallida(let mensaje):
        state.cargandoAuth = false
        state.errorMensaje = mensaje
        
    case .cerrarSesion:
        state.usuarioId = nil
        state.usuarioEmail = nil
        state.envios = []
        state.filtroEstado = nil
        
    case .iniciarEscuchaEnvios:
        state.cargandoEnvios = true
        
    case .enviosActualizados(let nuevosEnvios):
        state.cargandoEnvios = false
        state.envios = nuevosEnvios
        
    case .crearEnvio, .avanzarEstadoEnvio, .eliminarEnvio:
        state.errorMensaje = nil
        
    case .errorOperacion(let mensaje):
        state.cargandoEnvios = false
        state.errorMensaje = mensaje
        
    case .cambiarFiltro(let estado):
        state.filtroEstado = estado
        
    case .toggleInspectorRedux:
        state.mostrarInspectorRedux.toggle()
        
    case .limpiarError:
        state.errorMensaje = nil
    }
    
    let resumenNuevo = "Envíos: \(state.envios.count) | Auth: \(state.usuarioEmail ?? "nil")"
    let registro = RegistroAccionRedux(
        marcaTiempo: Date(),
        nombreAccion: action.descripcionCorta,
        resumenCambio: "\(resumenAnterior) → \(resumenNuevo)"
    )
    state.historialAcciones.insert(registro, at: 0)
    if state.historialAcciones.count > 25 {
        state.historialAcciones.removeLast()
    }
}

// MARK: - 5. STORE & MIDDLEWARE (Orquestador de Flujo Unidireccional y Efectos Firebase)
@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var state = AppState()
    
    private let db = Firestore.firestore()
    private var listenerRegistration: ListenerRegistration?
    
    init() {
        if let user = Auth.auth().currentUser, let email = user.email {
            dispatch(.authCompletada(uid: user.uid, email: email))
            dispatch(.iniciarEscuchaEnvios)
        }
    }
    
    func dispatch(_ action: AppAction) {
        // 1. Ejecutar el Reducer puro de forma síncrona
        appReducer(state: &state, action: action)
        
        // 2. Ejecutar Middleware (Efectos secundarios asíncronos con Firebase)
        ejecutarMiddleware(para: action)
    }
    
    private func traducirErrorAuth(_ error: NSError) -> String {
        let detalle = "\(error.userInfo)"
        if detalle.contains("INVALID_LOGIN_CREDENTIALS") {
            return "Correo o contraseña incorrectos. Verifica tus datos."
        } else if detalle.contains("EMAIL_EXISTS") {
            return "Este correo ya está registrado. Inicia sesión directamente."
        } else if detalle.contains("INVALID_EMAIL") {
            return "El formato del correo electrónico no es válido."
        } else if detalle.contains("WEAK_PASSWORD") {
            return "La contraseña debe tener al menos 6 caracteres."
        }
        return error.localizedDescription
    }
    
    private func ejecutarMiddleware(para action: AppAction) {
        switch action {
        case .iniciarSesion(let email, let password):
            let correoLimpio = email.trimmingCharacters(in: .whitespacesAndNewlines)
            Auth.auth().signIn(withEmail: correoLimpio, password: password) { [weak self] result, error in
                Task { @MainActor in
                    if let error = error as NSError? {
                        let mensajeAmigable = self?.traducirErrorAuth(error) ?? error.localizedDescription
                        self?.dispatch(.authFallida(mensajeAmigable))
                    } else if let user = result?.user {
                        self?.dispatch(.authCompletada(uid: user.uid, email: user.email ?? correoLimpio))
                        self?.dispatch(.iniciarEscuchaEnvios)
                    }
                }
            }
            
        case .registrarUsuario(let email, let password):
            let correoLimpio = email.trimmingCharacters(in: .whitespacesAndNewlines)
            Auth.auth().createUser(withEmail: correoLimpio, password: password) { [weak self] result, error in
                Task { @MainActor in
                    if let error = error as NSError? {
                        let mensajeAmigable = self?.traducirErrorAuth(error) ?? error.localizedDescription
                        self?.dispatch(.authFallida(mensajeAmigable))
                    } else if let user = result?.user {
                        self?.dispatch(.authCompletada(uid: user.uid, email: user.email ?? correoLimpio))
                        self?.dispatch(.iniciarEscuchaEnvios)
                    }
                }
            }
            
        case .cerrarSesion:
            listenerRegistration?.remove()
            listenerRegistration = nil
            try? Auth.auth().signOut()
            
        case .iniciarEscuchaEnvios:
            listenerRegistration?.remove()
            listenerRegistration = db.collection("envios")
                .order(by: "fechaCreacion", descending: true)
                .addSnapshotListener { [weak self] snapshot, error in
                    Task { @MainActor in
                        if let error = error {
                            self?.dispatch(.errorOperacion(error.localizedDescription))
                            return
                        }
                        guard let documentos = snapshot?.documents else { return }
                        let lista: [Envio] = documentos.compactMap { doc in
                            let data = doc.data()
                            guard let guia = data["codigoGuia"] as? String,
                                  let cliente = data["cliente"] as? String,
                                  let destino = data["destino"] as? String,
                                  let conductor = data["conductor"] as? String,
                                  let estadoRaw = data["estado"] as? String,
                                  let estado = EstadoEnvio(rawValue: estadoRaw) else {
                                return nil
                            }
                            let timestamp = data["fechaCreacion"] as? Timestamp
                            return Envio(
                                id: doc.documentID,
                                codigoGuia: guia,
                                cliente: cliente,
                                destino: destino,
                                conductor: conductor,
                                estado: estado,
                                fechaCreacion: timestamp?.dateValue() ?? Date()
                            )
                        }
                        self?.dispatch(.enviosActualizados(lista))
                    }
                }
            
        case .crearEnvio(let guia, let cliente, let destino, let conductor):
            let datos: [String: Any] = [
                "codigoGuia": guia,
                "cliente": cliente,
                "destino": destino,
                "conductor": conductor,
                "estado": EstadoEnvio.pendiente.rawValue,
                "fechaCreacion": Timestamp(date: Date())
            ]
            db.collection("envios").addDocument(data: datos) { [weak self] error in
                if let error = error {
                    Task { @MainActor in
                        self?.dispatch(.errorOperacion(error.localizedDescription))
                    }
                }
            }
            
        case .avanzarEstadoEnvio(let envio):
            let siguienteEstado: EstadoEnvio
            switch envio.estado {
            case .pendiente: siguienteEstado = .enRuta
            case .enRuta: siguienteEstado = .entregado
            case .entregado: siguienteEstado = .pendiente
            }
            db.collection("envios").document(envio.id).updateData([
                "estado": siguienteEstado.rawValue
            ]) { [weak self] error in
                if let error = error {
                    Task { @MainActor in
                        self?.dispatch(.errorOperacion(error.localizedDescription))
                    }
                }
            }
            
        case .eliminarEnvio(let id):
            db.collection("envios").document(id).delete { [weak self] error in
                if let error = error {
                    Task { @MainActor in
                        self?.dispatch(.errorOperacion(error.localizedDescription))
                    }
                }
            }
            
        default:
            break
        }
    }
}
