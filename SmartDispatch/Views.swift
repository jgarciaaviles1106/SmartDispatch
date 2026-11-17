import SwiftUI

// MARK: - VISTA RAÍZ (Enrutamiento según AppState)
struct RootView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        Group {
            if store.state.usuarioId != nil {
                DashboardDespachoView()
            } else {
                AuthView()
            }
        }
        .sheet(isPresented: Binding(
            get: { store.state.mostrarInspectorRedux },
            set: { _ in store.dispatch(.toggleInspectorRedux) }
        )) {
            InspectorReduxView()
                .environmentObject(store)
        }
    }
}

// MARK: - VISTA DE AUTENTICACIÓN (Firebase Auth)
struct AuthView: View {
    @EnvironmentObject var store: AppStore
    @State private var email = ""
    @State private var password = ""
    @State private var esRegistro = false

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "shippingbox.and.arrow.backward.fill")
                        .font(.system(size: 56))
                        .foregroundColor(.blue)
                    Text("SmartDispatch")
                        .font(.largeTitle.bold())
                    Text("Arquitectura Redux / Unidirectional Data Flow")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 20)

                VStack(spacing: 14) {
                    TextField("Correo electrónico institucional", text: $email)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)

                    SecureField("Contraseña (mínimo 6 caracteres)", text: $password)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)
                }

                if let error = store.state.errorMensaje {
                    Text(error)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }

                Button(action: {
                    if esRegistro {
                        store.dispatch(.registrarUsuario(email: email, password: password))
                    } else {
                        store.dispatch(.iniciarSesion(email: email, password: password))
                    }
                }) {
                    HStack {
                        if store.state.cargandoAuth {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        }
                        Text(esRegistro ? "Crear Cuenta de Operador" : "Iniciar Sesión")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(email.isEmpty || password.count < 6 ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(email.isEmpty || password.count < 6 || store.state.cargandoAuth)

                Button(esRegistro ? "¿Ya tienes cuenta? Inicia sesión" : "¿No tienes cuenta? Regístrate aquí") {
                    esRegistro.toggle()
                    store.dispatch(.limpiarError)
                }
                .font(.footnote)

                Spacer()
            }
            .padding()
            .navigationBarHidden(true)
        }
    }
}

// MARK: - PANEL PRINCIPAL DE LOGÍSTICA (CRUD Cloud Firestore + Redux)
struct DashboardDespachoView: View {
    @EnvironmentObject var store: AppStore
    @State private var mostrarNuevoEnvio = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Tarjetas de métricas en tiempo real derivadas del AppState
                HStack(spacing: 10) {
                    TarjetaMetrica(titulo: "Total", valor: "\(store.state.envios.count)", color: .blue)
                    TarjetaMetrica(
                        titulo: "Pendientes",
                        valor: "\(store.state.envios.filter { $0.estado == .pendiente }.count)",
                        color: .orange
                    )
                    TarjetaMetrica(
                        titulo: "En Ruta",
                        valor: "\(store.state.envios.filter { $0.estado == .enRuta }.count)",
                        color: .purple
                    )
                    TarjetaMetrica(
                        titulo: "Entregados",
                        valor: "\(store.state.envios.filter { $0.estado == .entregado }.count)",
                        color: .green
                    )
                }
                .padding()

                // Selector de filtro por estado (Despacha Action .cambiarFiltro)
                Picker("Filtrar por estado", selection: Binding(
                    get: { store.state.filtroEstado },
                    set: { store.dispatch(.cambiarFiltro($0)) }
                )) {
                    Text("Todos").tag(EstadoEnvio?.none)
                    ForEach(EstadoEnvio.allCases, id: \.self) { estado in
                        Text(estado.rawValue).tag(EstadoEnvio?.some(estado))
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
                .padding(.bottom, 8)

                if store.state.cargandoEnvios && store.state.envios.isEmpty {
                    Spacer()
                    ProgressView("Sincronizando con Cloud Firestore...")
                    Spacer()
                } else if store.state.enviosFiltrados.isEmpty {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(systemName: "tray")
                            .font(.system(size: 42))
                            .foregroundColor(.secondary)
                        Text("No hay órdenes de despacho registradas")
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                } else {
                    List {
                        ForEach(store.state.enviosFiltrados) { envio in
                            FilaEnvioView(
                                envio: envio,
                                onAvanzarEstado: {
                                    store.dispatch(.avanzarEstadoEnvio(envio))
                                },
                                onEliminar: {
                                    store.dispatch(.eliminarEnvio(envio.id))
                                }
                            )
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                let envio = store.state.enviosFiltrados[index]
                                store.dispatch(.eliminarEnvio(envio.id))
                            }
                        }
                    }
                    .listStyle(InsetGroupedListStyle())
                }
            }
            .navigationTitle("SmartDispatch")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        store.dispatch(.cerrarSesion)
                    }) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .foregroundColor(.red)
                    }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    // Botón Factor Wow: Abre el monitor en vivo de acciones Redux
                    Button(action: {
                        store.dispatch(.toggleInspectorRedux)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "waveform.path.ecg")
                            Text("\(store.state.historialAcciones.count)")
                                .font(.caption.bold())
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.indigo.opacity(0.15))
                        .foregroundColor(.indigo)
                        .cornerRadius(8)
                    }

                    Button(action: {
                        mostrarNuevoEnvio = true
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                }
            }
            .sheet(isPresented: $mostrarNuevoEnvio) {
                NuevoEnvioSheet()
                    .environmentObject(store)
            }
        }
    }
}

struct TarjetaMetrica: View {
    let titulo: String
    let valor: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(valor)
                .font(.title2.bold())
                .foregroundColor(color)
            Text(titulo)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }
}

struct FilaEnvioView: View {
    let envio: Envio
    let onAvanzarEstado: () -> Void
    let onEliminar: () -> Void

    var colorEstado: Color {
        switch envio.estado {
        case .pendiente: return .orange
        case .enRuta: return .purple
        case .entregado: return .green
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(envio.codigoGuia)
                    .font(.headline)
                Spacer()
                Button(action: onAvanzarEstado) {
                    Text(envio.estado.rawValue)
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(colorEstado.opacity(0.18))
                        .foregroundColor(colorEstado)
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())

                Button(action: onEliminar) {
                    Image(systemName: "trash")
                        .font(.caption.bold())
                        .padding(6)
                        .background(Color.red.opacity(0.15))
                        .foregroundColor(.red)
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
            }

            Text("Cliente: \(envio.cliente)")
                .font(.subheadline)
            HStack {
                Label(envio.destino, systemImage: "mappin.and.ellipse")
                Spacer()
                Label(envio.conductor, systemImage: "car.fill")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - FORMULARIO DE NUEVO DESPACHO
struct NuevoEnvioSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.presentationMode) var presentationMode

    @State private var codigoGuia = "SD-\(Int.random(in: 1000...9999))"
    @State private var cliente = ""
    @State private var destino = ""
    @State private var conductor = ""

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Identificación de Guía")) {
                    TextField("Código de Guía", text: $codigoGuia)
                }
                Section(header: Text("Datos de Entrega")) {
                    TextField("Nombre del Cliente / Empresa", text: $cliente)
                    TextField("Dirección o Zona de Destino", text: $destino)
                    TextField("Conductor Asignado", text: $conductor)
                }
            }
            .navigationTitle("Nuevo Despacho")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Despachar") {
                        store.dispatch(.crearEnvio(
                            codigoGuia: codigoGuia,
                            cliente: cliente,
                            destino: destino,
                            conductor: conductor
                        ))
                        presentationMode.wrappedValue.dismiss()
                    }
                    .disabled(cliente.isEmpty || destino.isEmpty || conductor.isEmpty)
                }
            }
        }
    }
}

// MARK: - INSPECTOR DE FLUJO UNIDIRECCIONAL REDUX ("FACTOR WOW")
struct InspectorReduxView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Estado Global Actual (AppState)")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Operador Activo: \(store.state.usuarioEmail ?? "Ninguno")")
                        Text("Documentos en Memoria: \(store.state.envios.count)")
                        Text("Filtro Activo: \(store.state.filtroEstado?.rawValue ?? "Todos")")
                    }
                    .font(.caption.monospaced())
                }

                Section(header: Text("Flujo de Acciones y Transiciones Reducer")) {
                    ForEach(store.state.historialAcciones) { registro in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(registro.nombreAccion)
                                    .font(.caption.bold().monospaced())
                                    .foregroundColor(.indigo)
                                Spacer()
                                Text(registro.marcaTiempo, style: .time)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Text(registro.resumenCambio)
                                .font(.caption2.monospaced())
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("Inspector Redux")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cerrar") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}

struct RootView_Previews: PreviewProvider {
    static var previews: some View {
        RootView()
            .environmentObject(AppStore())
    }
}

