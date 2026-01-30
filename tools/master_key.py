import hashlib
import sys

def generate_master_key(code):
    """
    Genera una clave maestra de 6 dígitos alfanuméricos basada en el código de sesión.
    Debe coincidir con el algoritmo implementado en el firmware (C++) y la app (Dart).
    """
    if not code:
        return "Error: Código vacío"
    
    # SALT: Palabra secreta que debe estar IGUAL en el código del firmware/app.
    # Esto evita que alguien adivine la clave solo sabiendo el algoritmo.
    secret_salt = "Hiroki_Security_2026_Salt"
    
    # Concatenar code + salt
    data = f"{code}{secret_salt}".encode('utf-8')
    
    # Generar Hash SHA-256
    hash_object = hashlib.sha256(data)
    hex_digest = hash_object.hexdigest()
    
    # Tomar los primeros 6 caracteres y convertirlos a mayúsculas
    master_key = hex_digest[:6].upper()
    
    return master_key

if __name__ == "__main__":
    print("--- Generador de Clave Maestra Hiroki ---")
    if len(sys.argv) > 1:
        session_code_input = sys.argv[1]
    else:
        session_code_input = input("Ingrese el Código de Sesión que muestra la app: ").strip().upper()
    
    if session_code_input:
        key = generate_master_key(session_code_input)
        print(f"\nCódigo de Sesión: {session_code_input}")
        print(f"CLAVE MAESTRA: {key}")
        print("\n(Use esta clave para acceder a la configuración técnica)")
    else:
        print("Código de sesión inválido.")
