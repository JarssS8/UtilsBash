#!/usr/bin/env python3
"""Alta masiva de dispositivos en ChirpStack usando Selenium.

Requisitos:
  pip install selenium

Uso:
  python3 scripts/chirpstack_bulk_create.py                    # menú interactivo
  python3 scripts/chirpstack_bulk_create.py --action create    # crear dispositivos
  python3 scripts/chirpstack_bulk_create.py --action multicast # seleccionar en grupo multicast
"""

from __future__ import annotations

import argparse
import json
import os
import time
from dataclasses import dataclass
from pathlib import Path

from dotenv import load_dotenv
from selenium import webdriver
from selenium.common.exceptions import TimeoutException
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.common.by import By
from selenium.webdriver.common.keys import Keys
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.support.ui import WebDriverWait
from tqdm import tqdm

load_dotenv()

CHIRPSTACK_URL = os.getenv("CHIRPSTACK_URL", "http://chirpstack.pappstor.com").rstrip("/")
CHIRPSTACK_TENANT_ID = os.getenv("CHIRPSTACK_TENANT_ID", "00000000-0000-0000-0000-000000000001")
CHIRPSTACK_APP_ID = os.getenv("CHIRPSTACK_APP_ID", "00000000-0000-0000-0000-000000000007")

LOGIN_URL = CHIRPSTACK_URL
CREATE_DEVICE_URL = f"{CHIRPSTACK_URL}/#/tenants/{CHIRPSTACK_TENANT_ID}/applications/{CHIRPSTACK_APP_ID}/devices/create"
DEVICES_LIST_URL = f"{CHIRPSTACK_URL}/#/tenants/{CHIRPSTACK_TENANT_ID}/applications/{CHIRPSTACK_APP_ID}"
USERNAME = os.getenv("CHIRPSTACK_USERNAME")
PASSWORD = os.getenv("CHIRPSTACK_PASSWORD")

PAPPSTOR_URL = os.getenv("PAPPSTOR_URL", "https://pappstor-admin-dev.web.app").rstrip("/")
PAPPSTOR_LOGIN_URL = f"{PAPPSTOR_URL}/login"
PAPPSTOR_SENSORS_URL = f"{PAPPSTOR_URL}/sensors"
PAPPSTOR_USERNAME = os.getenv("PAPPSTOR_USERNAME")
PAPPSTOR_PASSWORD = os.getenv("PAPPSTOR_PASSWORD")

JOIN_EUI = "0101010101010101"
DEVICE_PROFILE = os.getenv("CHIRPSTACK_DEVICE_PROFILE", "Hesia Multicast")


@dataclass
class Device:
    name: str
    dev_eui: str


def build_driver(headless: bool = True) -> webdriver.Chrome:
    options = Options()
    options.set_capability("acceptInsecureCerts", True)
    options.add_argument("--ignore-certificate-errors")
    options.add_argument("--start-maximized")
    if headless:
        options.add_argument("--headless=new")
    return webdriver.Chrome(options=options)


def first_visible(wait: WebDriverWait, selectors: list[str]):
    end = time.time() + wait._timeout
    last_exc = None
    while time.time() < end:
        for sel in selectors:
            try:
                el = wait._driver.find_element(By.CSS_SELECTOR, sel)
                if el.is_displayed() and el.is_enabled():
                    return el
            except Exception as exc:  # noqa: BLE001
                last_exc = exc
        time.sleep(0.2)
    raise TimeoutException(f"No encontré elemento visible para: {selectors}") from last_exc


def set_text(driver: webdriver.Chrome, by: By, locator: str, value: str, timeout: int = 20) -> None:
    el = WebDriverWait(driver, timeout).until(EC.element_to_be_clickable((by, locator)))
    el.click()
    el.clear()
    el.send_keys(value)


def ensure_switch_on(driver: webdriver.Chrome, switch_id: str, timeout: int = 20) -> None:
    btn = WebDriverWait(driver, timeout).until(EC.presence_of_element_located((By.ID, switch_id)))
    if btn.get_attribute("aria-checked") != "true":
        WebDriverWait(driver, timeout).until(EC.element_to_be_clickable((By.ID, switch_id))).click()
        WebDriverWait(driver, timeout).until(
            lambda d: d.find_element(By.ID, switch_id).get_attribute("aria-checked") == "true"
        )


def select_device_profile(driver: webdriver.Chrome, profile_name: str, timeout: int = 20) -> None:
    # Abrimos el dropdown con JS click para evitar que el span intercepte.
    container = WebDriverWait(driver, timeout).until(
        EC.presence_of_element_located(
            (
                By.XPATH,
                "//label[@for='deviceProfileId']/ancestor::div[contains(@class,'ant-form-item')]"
                "//div[contains(@class,'ant-select-selector')]",
            )
        )
    )
    driver.execute_script("arguments[0].click();", container)

    # Escribimos el nombre en el input de búsqueda para filtrar.
    search_input = WebDriverWait(driver, timeout).until(
        EC.presence_of_element_located(
            (
                By.XPATH,
                "//label[@for='deviceProfileId']/ancestor::div[contains(@class,'ant-form-item')]"
                "//input[@type='search']",
            )
        )
    )
    search_input.clear()
    search_input.send_keys(profile_name)
    time.sleep(0.5)  # Pequeña pausa para que el dropdown filtre.

    # Buscamos por texto visible: cualquier ant-select-item que contenga el nombre.
    option = WebDriverWait(driver, timeout).until(
        EC.element_to_be_clickable(
            (By.XPATH, f"//div[contains(@class,'ant-select-item') and contains(normalize-space(.),'{profile_name}')]")
        )
    )
    driver.execute_script("arguments[0].scrollIntoView(true);", option)
    driver.execute_script("arguments[0].click();", option)


def login(driver: webdriver.Chrome) -> None:
    if not USERNAME or not PASSWORD:
        raise ValueError("Credenciales de ChirpStack no encontradas. Verifica tu archivo .env (CHIRPSTACK_USERNAME, CHIRPSTACK_PASSWORD).")

    wait = WebDriverWait(driver, 30)
    driver.get(LOGIN_URL)
    wait.until(EC.presence_of_element_located((By.TAG_NAME, "body")))

    user_input = first_visible(
        wait,
        [
            "input[name='email']",
            "input[name='username']",
            "input#email",
            "input#username",
            "input[autocomplete='username']",
            "input[type='text']",
        ],
    )
    pass_input = first_visible(
        wait,
        [
            "input[name='password']",
            "input#password",
            "input[autocomplete='current-password']",
            "input[type='password']",
        ],
    )

    user_input.clear()
    user_input.send_keys(USERNAME)
    pass_input.clear()
    pass_input.send_keys(PASSWORD)

    login_btn = first_visible(
        wait,
        [
            "button[type='submit']",
            "button.ant-btn-primary",
            "button[class*='login']",
        ],
    )
    login_btn.click()

    wait.until(lambda d: "login" not in d.current_url.lower())


def create_device(driver: webdriver.Chrome, device: Device) -> None:
    driver.get(CREATE_DEVICE_URL)
    WebDriverWait(driver, 30).until(EC.presence_of_element_located((By.ID, "name")))

    set_text(driver, By.ID, "name", device.name)
    set_text(driver, By.ID, "devEuiRender", device.dev_eui)
    set_text(driver, By.ID, "joinEuiRender", JOIN_EUI)
    select_device_profile(driver, DEVICE_PROFILE)
    ensure_switch_on(driver, "skipFcntCheck")

    submit_btn = WebDriverWait(driver, 20).until(
        EC.element_to_be_clickable((By.XPATH, "//button[@type='submit']//span[normalize-space()='Submit']/.."))
    )
    submit_btn.click()

    WebDriverWait(driver, 30).until(lambda d: "/devices/create" not in d.current_url)


def set_page_size_100(driver: webdriver.Chrome, timeout: int = 30) -> None:
    """Cambia el paginador a 100 elementos por página escribiendo directamente."""
    # Esperamos a que el paginador sea clickable (indica que la tabla terminó de cargar).
    paginator_li = WebDriverWait(driver, timeout).until(
        EC.element_to_be_clickable((By.XPATH, "//li[contains(@class,'ant-pagination-options')]"))
    )
    driver.execute_script("arguments[0].scrollIntoView({block:'center'});", paginator_li)
    time.sleep(0.5)

    # JS click en el span "10 / page" para abrir el selector.
    paginator_span = paginator_li.find_element(
        By.XPATH, ".//span[contains(@class,'ant-select-selection-item')]"
    )
    driver.execute_script("arguments[0].click();", paginator_span)
    time.sleep(0.5)

    # El input ahora está accessible — escribimos 100 y Enter.
    page_input = WebDriverWait(driver, timeout).until(
        EC.presence_of_element_located((By.CSS_SELECTOR, "input[aria-label='Page Size']"))
    )
    driver.execute_script("arguments[0].value = '';", page_input)
    driver.execute_script("arguments[0].focus();", page_input)
    page_input.send_keys("100")
    page_input.send_keys(Keys.RETURN)
    time.sleep(2.0)  # Esperamos a que la tabla recargue con 100 filas.
    print("  [paginador] 100 dispositivos por página seleccionado")


def find_and_select_in_current_page(driver: webdriver.Chrome, dev_eui: str) -> bool:
    """Busca el devEUI en la página actual (sin esperar). Devuelve True si lo encuentra y selecciona."""
    try:
        row = driver.find_element(By.XPATH, f"//tr[@data-row-key='{dev_eui}']")
        checkbox_input = row.find_element(By.XPATH, ".//input[@type='checkbox']")
        if not checkbox_input.is_selected():
            label = row.find_element(By.XPATH, ".//label[contains(@class,'ant-checkbox-wrapper')]")
            driver.execute_script("arguments[0].click();", label)
        return True
    except Exception:  # noqa: BLE001
        return False


def has_next_page(driver: webdriver.Chrome) -> bool:
    """Devuelve True si el botón 'siguiente página' existe y no está deshabilitado."""
    try:
        next_btn = driver.find_element(By.XPATH, "//li[contains(@class,'ant-pagination-next')]")
        return "ant-pagination-disabled" not in next_btn.get_attribute("class")
    except Exception:  # noqa: BLE001
        return False


def go_to_next_page(driver: webdriver.Chrome, timeout: int = 15) -> None:
    """Hace click en el botón siguiente de la paginación y espera a que la tabla recargue."""
    next_btn = driver.find_element(By.XPATH, "//li[contains(@class,'ant-pagination-next')]//button | //li[contains(@class,'ant-pagination-next')]")
    driver.execute_script("arguments[0].click();", next_btn)
    time.sleep(1.2)  # Esperamos a que cargue la nueva página.


def run_pappstor(driver: webdriver.Chrome, devices: list[Device], raza: str, compania: str, red: str) -> None:
    """Acción: dar de alta collares en Pappstor Admin."""
    print(f"\n[Pappstor Admin] Iniciando alta de {len(devices)} dispositivos...")
    print(f"  Raza/Especie: {raza} | Compañía: {compania} | Red: {red}")

    if not PAPPSTOR_USERNAME or not PAPPSTOR_PASSWORD:
        raise ValueError("Credenciales de Pappstor no encontradas. Verifica tu archivo .env.")

    wait = WebDriverWait(driver, 30)

    # 1. Login
    driver.get(PAPPSTOR_LOGIN_URL)
    print("  [login] Cargando página de login de Pappstor...")
    
    email_input = first_visible(
        wait,
        ["input[type='email']", "input[name='email']", "input[name='usuario']"]
    )
    pass_input = first_visible(
        wait,
        ["input[type='password']", "input[name='password']", "input[name='contraseña']"]
    )
    
    email_input.clear()
    email_input.send_keys(PAPPSTOR_USERNAME)
    pass_input.clear()
    pass_input.send_keys(PAPPSTOR_PASSWORD)
    time.sleep(0.5)
    
    # Buscar el botón de login y hacer click (esperando a que no esté disabled)
    login_btn = wait.until(
        EC.element_to_be_clickable(
            (By.XPATH, "//button[.//span[text()='Iniciar sesión'] or contains(translate(., 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz'), 'iniciar sesión')]")
        )
    )
    driver.execute_script("arguments[0].click();", login_btn)
    
    # Esperamos a salir de la pantalla de login
    wait.until(lambda d: "login" not in d.current_url.lower())
    print("  [login] Login correcto en Pappstor.")

    # 2. Navegar a Sensores/Collares
    driver.get(PAPPSTOR_SENSORS_URL)
    print("  [navegación] Cargando lista de sensores...")
    time.sleep(2) # Esperar a que cargue la SPA

    failed: list[tuple[Device, str]] = []

    for device in tqdm(devices, desc="Alta en Pappstor", unit="disp"):
        try:
            # Click en Nuevo Collar (buscando exactamente el texto del label proporcionado)
            nuevo_btn = wait.until(
                EC.element_to_be_clickable(
                    (By.XPATH, "//button[.//span[contains(text(), 'Nueva collar')]]")
                )
            )
            driver.execute_script("arguments[0].click();", nuevo_btn)
            time.sleep(1.5) # Esperar a que el modal se anime y abra completa mente

            # Llenar DevEUI (Número de serie)
            # Buscamos el input por su formcontrolname o por estar dentro del mat-form-field correspondiente
            serie_input = wait.until(
                EC.presence_of_element_located(
                    (By.XPATH, "//input[@formcontrolname='serialNumber']")
                )
            )
            serie_input.clear()
            serie_input.send_keys(device.dev_eui)

            # Función helper para seleccionar en dropdowns de Angular Material
            def select_material_dropdown(formcontrolname: str, option_text: str):
                # 1. Encontrar el mat-select y hacer click para abrir las opciones
                dropdown = wait.until(
                    EC.element_to_be_clickable(
                        (By.XPATH, f"//mat-select[@formcontrolname='{formcontrolname}']")
                    )
                )
                driver.execute_script("arguments[0].scrollIntoView(true);", dropdown)
                time.sleep(0.3)
                driver.execute_script("arguments[0].click();", dropdown)
                time.sleep(0.5) # Esperar a que se anime el panel flotante
                
                # 2. Buscar la opción por texto en el overlay (suele ser mat-option)
                # Angular Material adjunta las opciones al body en un cdk-overlay-container
                # Usamos una comparación exacta para evitar que "HesiaSensor" coincida con "ItelazpiHesiaSensor"
                option = wait.until(
                    EC.element_to_be_clickable(
                        (By.XPATH, f"//mat-option[normalize-space(.)='{option_text}' or translate(normalize-space(.), 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz')='{option_text.lower()}']")
                    )
                )
                driver.execute_script("arguments[0].click();", option)
                time.sleep(0.3)

            # Seleccionar Red
            select_material_dropdown("networkType", red)
            
            # Seleccionar Especie/Raza
            select_material_dropdown("speciesId", raza)

            # Seleccionar Compañía
            select_material_dropdown("companyId", compania)

            # Click en Crear collar
            guardar_btn = wait.until(
                EC.element_to_be_clickable(
                    (By.XPATH, "//button[.//span[contains(text(), 'Crear collar')]]")
                )
            )
            driver.execute_script("arguments[0].click();", guardar_btn)
            time.sleep(1) # Esperar a que cambie la vista del modal

            # Nuevo paso: Hacer click en el botón "Confirmar" (pantalla de ¿Seguro que todos los datos están correctos?)
            confirmar_btn = wait.until(
                EC.element_to_be_clickable(
                    (By.XPATH, "//button[@type='submit' and .//span[contains(text(), 'Confirmar')]]")
                )
            )
            driver.execute_script("arguments[0].click();", confirmar_btn)
            time.sleep(1.5) # Esperar a que se guarde en backend y cambie la vista

            # Nuevo paso: Hacer click en el botón "Salir" (pantalla final de Datos del collar)
            salir_btn = wait.until(
                EC.element_to_be_clickable(
                    (By.XPATH, "//button[@mat-dialog-close and .//span[contains(text(), 'Salir')]]")
                )
            )
            driver.execute_script("arguments[0].click();", salir_btn)
            time.sleep(1) # Esperar a que el modal se cierre completamente

        except Exception as exc:
            failed.append((device, str(exc)))
            screenshot_path = Path(__file__).parent / f"error_pappstor_{device.dev_eui}.png"
            try:
                driver.save_screenshot(str(screenshot_path))
                tqdm.write(f"  [screenshot] Guardado en {screenshot_path}")
            except Exception:
                pass
            tqdm.write(f"✗ ERROR -> {device.dev_eui} :: {exc}")
            
            # Intentar refrescar la página para el siguiente
            driver.get(PAPPSTOR_SENSORS_URL)
            time.sleep(2)

    print("\n=== Resumen Pappstor ===")
    print(f"Total: {len(devices)}")
    print(f"Fallidos: {len(failed)}")
    if failed:
        print("Detalle de fallos:")
        for d, err in failed:
            print(f"  - {d.dev_eui}: {err}")

def run_create(driver: webdriver.Chrome, devices: list[Device]) -> None:
    """Acción: crear dispositivos uno a uno."""
    failed: list[tuple[Device, str]] = []

    print("Haciendo login en ChirpStack...")
    login(driver)
    print("Login correcto\n")

    for device in tqdm(devices, desc="Creando dispositivos", unit="disp"):
        try:
            create_device(driver, device)
            # tqdm.write(f"✓ OK -> {device.name} ({device.dev_eui})")
        except Exception as exc:  # noqa: BLE001
            failed.append((device, str(exc)))
            screenshot_path = Path(__file__).parent / f"error_{device.dev_eui}.png"
            try:
                driver.save_screenshot(str(screenshot_path))
                tqdm.write(f"  [screenshot] Guardado en {screenshot_path}")
            except Exception:  # noqa: BLE001
                pass
            tqdm.write(f"✗ ERROR -> {device.name} ({device.dev_eui}) :: {exc}")
            time.sleep(1)

    print("\n=== Resumen ===")
    print(f"Total: {len(devices)}")
    print(f"Fallidos: {len(failed)}")
    if failed:
        print("Detalle de fallos:")
        for d, err in failed:
            print(f"  - {d.name} ({d.dev_eui}): {err}")


def add_to_multicast_group(driver: webdriver.Chrome, group_name: str, timeout: int = 20) -> None:
    """Abre el menú 'Selected devices', elige 'Add to multicast-group' y confirma el modal."""
    # Screenshot de diagnóstico para ver el estado actual de la UI.
    debug_path = Path(__file__).parent / "debug_selected_btn.png"
    driver.save_screenshot(str(debug_path))

    # Dump de todos los botones visibles para diagnosticar.
    btns_text = driver.execute_script(
        "return Array.from(document.querySelectorAll('button')).map(b => b.innerText.trim()).filter(t => t).join(' | ');"
    )
    print(f"  [debug] Botones en página: {btns_text}")

    # Buscamos cualquier botón o elemento que contenga 'selected' en su texto.
    selected_btn = WebDriverWait(driver, timeout).until(
        EC.element_to_be_clickable(
            (By.XPATH, "//*[self::button or self::span or self::a][contains(., 'selected') or contains(., 'Selected')]")
        )
    )
    driver.execute_script("arguments[0].click();", selected_btn)
    time.sleep(0.4)

    # Hacemos click en la opción 'Add to multicast-group' del dropdown
    multicast_option = WebDriverWait(driver, timeout).until(
        EC.element_to_be_clickable(
            (By.XPATH, "//li[contains(@class, 'ant-dropdown-menu-item')]//span[text()='Add to multicast-group']")
        )
    )
    driver.execute_script("arguments[0].click();", multicast_option)
    time.sleep(0.5)

    # Esperamos a que aparezca el modal
    WebDriverWait(driver, timeout).until(
        EC.presence_of_element_located((By.CLASS_NAME, "ant-modal-content"))
    )
    print(f"  [modal] Modal de multicast abierto")

    # Abrimos el selector del grupo dentro del modal
    modal_selector = WebDriverWait(driver, timeout).until(
        EC.presence_of_element_located(
            (By.XPATH, "//div[@class='ant-modal-content']//div[contains(@class,'ant-select-selector')]")
        )
    )
    driver.execute_script("arguments[0].click();", modal_selector)
    time.sleep(0.5)

    # Tratamos de escribir en el input interno para filtrar (si el componente lo permite)
    try:
        search_input = modal_selector.find_element(By.XPATH, ".//input")
        search_input.send_keys(group_name)
        time.sleep(0.5)
    except Exception:
        pass

    # Buscamos la opción que coincide con el nombre del grupo (por texto visible)
    group_option = WebDriverWait(driver, timeout).until(
        EC.element_to_be_clickable(
            (By.XPATH, f"//div[contains(@class,'ant-select-item') and contains(normalize-space(.),'{group_name}')]")
        )
    )
    driver.execute_script("arguments[0].scrollIntoView(true);", group_option)
    driver.execute_script("arguments[0].click();", group_option)
    time.sleep(0.5)
    print(f"  [modal] Grupo '{group_name}' seleccionado")

    # Hacemos click en el botón OK del modal
    ok_btn = WebDriverWait(driver, timeout).until(
        EC.element_to_be_clickable(
            (By.XPATH, "//div[@class='ant-modal-footer']//button[contains(@class,'ant-btn-primary') and not(@disabled)]")
        )
    )
    driver.execute_script("arguments[0].click();", ok_btn)
    time.sleep(0.8)
    print(f"  [modal] Confirmado — dispositivos añadidos al grupo '{group_name}'")


def run_status(driver: webdriver.Chrome, devices: list[Device]) -> None:
    """Acción: seleccionar dispositivos por páginas solo para visualizarlos, sin hacer nada más."""

    login(driver)
    print("Login correcto\n")

    # Navegamos a la lista de dispositivos
    driver.get(DEVICES_LIST_URL)
    WebDriverWait(driver, 30).until(
        EC.presence_of_element_located((By.CLASS_NAME, "ant-table-row"))
    )
    print("  [navegación] Lista de dispositivos cargada")
    time.sleep(1.5)

    # Cambiamos la paginación a 100 por página
    set_page_size_100(driver)

    # Conjunto de dispositivos pendientes de seleccionar
    pending: dict[str, Device] = {d.dev_eui: d for d in devices}
    selected_total: list[Device] = []
    not_found: list[Device] = []

    with tqdm(total=len(devices), desc="Verificando estado", unit="disp") as pbar:
        while pending:
            found_on_page: list[str] = []

            for dev_eui, device in list(pending.items()):
                if find_and_select_in_current_page(driver, dev_eui):
                    selected_total.append(device)
                    found_on_page.append(dev_eui)
                    pbar.update(1)

            # Eliminamos los encontrados del conjunto pendiente
            for dev_eui in found_on_page:
                del pending[dev_eui]

            if not pending:
                break

            if has_next_page(driver):
                go_to_next_page(driver)
            else:
                not_found = list(pending.values())
                break

    print(f"\n=== Resumen ===")
    print(f"Total: {len(devices)}")
    print(f"Seleccionados: {len(selected_total)}")
    print(f"No encontrados: {len(not_found)}")
    if not_found:
        print("Dispositivos no encontrados en ninguna página:")
        for d in not_found:
            print(f"  - {d.name} ({d.dev_eui})")

    input("\nPresiona Enter para cerrar el navegador y terminar...")


def run_multicast(driver: webdriver.Chrome, devices: list[Device], group_name: str) -> None:
    """Acción: seleccionar dispositivos por páginas y añadirlos al grupo multicast."""

    login(driver)
    print("Login correcto\n")

    # Navegamos a la lista de dispositivos
    driver.get(DEVICES_LIST_URL)
    WebDriverWait(driver, 30).until(
        EC.presence_of_element_located((By.CLASS_NAME, "ant-table-row"))
    )
    print("  [navegación] Lista de dispositivos cargada")
    time.sleep(1.5)  # Pausa extra para que React termine de renderizar la paginación.

    # Cambiamos la paginación a 100 por página
    set_page_size_100(driver)

    # Conjunto de dispositivos pendientes de seleccionar
    pending: dict[str, Device] = {d.dev_eui: d for d in devices}
    selected_total: list[Device] = []
    not_found: list[Device] = []

    with tqdm(total=len(devices), desc="Asignando a grupo", unit="disp") as pbar:
        while pending:
            found_on_page: list[str] = []

            for dev_eui, device in list(pending.items()):
                if find_and_select_in_current_page(driver, dev_eui):
                    selected_total.append(device)
                    found_on_page.append(dev_eui)
                    pbar.update(1)

            # Si se encontró alguno en esta página, los añadimos al grupo antes de pasar.
            if found_on_page:
                try:
                    add_to_multicast_group(driver, group_name)
                except Exception as exc:  # noqa: BLE001
                    tqdm.write(f"  ✗ Error añadiendo al grupo en la página actual: {exc}")

            # Eliminamos los encontrados del conjunto pendiente
            for dev_eui in found_on_page:
                del pending[dev_eui]

            if not pending:
                break  # Todos procesados.

            if has_next_page(driver):
                go_to_next_page(driver)
            else:
                not_found = list(pending.values())
                break

    print(f"\n=== Resumen ===")
    print(f"Total: {len(devices)}")
    print(f"Procesados: {len(selected_total)}")
    print(f"No encontrados: {len(not_found)}")
    if not_found:
        print("Dispositivos no encontrados en ninguna página:")
        for d in not_found:
            print(f"  - {d.name} ({d.dev_eui})")


def load_devices(path: Path) -> list[Device]:
    raw = json.loads(path.read_text(encoding="utf-8"))
    devices: list[Device] = []
    for i, item in enumerate(raw, start=1):
        if not isinstance(item, dict):
            raise ValueError(f"Entrada {i}: debe ser objeto JSON")
        name = item.get("name")
        dev_eui = item.get("devEui")
        if not name or not dev_eui:
            raise ValueError(f"Entrada {i}: faltan campos 'name' o 'devEui'")
        devices.append(Device(str(name), str(dev_eui)))
    return devices


def ask_choice(prompt_text: str, options: list[str]) -> str:
    """Muestra un menú de opciones y devuelve la seleccionada."""
    print(f"\n{prompt_text}")
    for i, opt in enumerate(options, start=1):
        print(f"  {i}) {opt}")
    while True:
        try:
            choice = int(input(f"Elige una opción (1-{len(options)}): ").strip())
            if 1 <= choice <= len(options):
                return options[choice - 1]
        except ValueError:
            pass
        print("Opción no válida. Inténtalo de nuevo.")


def ask_action() -> str:
    """Muestra un menú interactivo para elegir la acción."""
    print("=" * 50)
    print("  ChirpStack Bulk Tool")
    print("=" * 50)
    print()
    print("  1) Crear dispositivos")
    print("  2) Seleccionar dispositivos para grupo multicast")
    print("  3) Alta de collares en Pappstor Admin")
    print("  4) Ver estado (sólo seleccionar, no hacer nada más)")
    print()
    while True:
        choice = input("Elige una opción (1/2/3/4): ").strip()
        if choice == "1":
            return "create"
        if choice == "2":
            return "multicast"
        if choice == "3":
            return "pappstor"
        if choice == "4":
            return "status"
        print("Opción no válida. Introduce 1, 2, 3 o 4.")


def parse_args() -> argparse.Namespace:
    default_devices_file = Path(__file__).resolve().parent / "chirpstack_devices.json"
    parser = argparse.ArgumentParser(description="Alta masiva de dispositivos en ChirpStack y Pappstor")
    parser.add_argument(
        "--devices-file",
        default=str(default_devices_file),
        help="Ruta al JSON con la lista de dispositivos",
    )
    parser.add_argument(
        "--action",
        choices=["create", "multicast", "pappstor", "status"],
        default=None,
        help="Acción a realizar: 'create', 'multicast', 'pappstor' o 'status'",
    )
    parser.add_argument(
        "multicast_group",
        nargs="?",
        default=None,
        help="Nombre del grupo multicast al que añadir los dispositivos (solo para --action multicast)",
    )
    parser.add_argument(
        "--wb",
        action="store_true",
        help="Mostrar el navegador web (con UI) en lugar de ejecutar en modo headless",
    )
    return parser.parse_args()


def main() -> None:
    # Validar variables de entorno críticas al inicio
    required_vars = [
        "CHIRPSTACK_USERNAME", "CHIRPSTACK_PASSWORD", "CHIRPSTACK_URL",
        "PAPPSTOR_USERNAME", "PAPPSTOR_PASSWORD", "PAPPSTOR_URL"
    ]
    missing = [v for v in required_vars if not os.getenv(v)]
    if missing:
        print("\nERROR: Faltan variables de entorno críticas en el archivo .env:")
        for v in missing:
            print(f"  - {v}")
        print("\nPor favor, asegúrate de tener un archivo .env configurado correctamente.")
        print("Puedes usar .env.example como referencia.\n")
        return

    args = parse_args()
    devices_file = Path(args.devices_file).expanduser().resolve()
    devices = load_devices(devices_file)

    action = args.action or ask_action()

    print(f"\nDispositivos cargados: {len(devices)}")
    
    # Recoger datos adicionales antes de abrir el navegador
    group_name = None
    raza = None
    compania = None
    red = None

    if action == "create":
        print("Acción: Crear dispositivos\n")
    elif action == "multicast":
        print("Acción: Asignar a grupo multicast")
        group_name = args.multicast_group
        if not group_name:
            group_name = input("Nombre del grupo multicast: ").strip()
        print(f"Grupo multicast: {group_name}\n")
    elif action == "pappstor":
        print("Acción: Alta de collares en Pappstor Admin")
        razas = ["Ovino", "Bovino", "Equino"]
        redes = ["ItelazpiHesiaSensor", "HesiaSensor"]
        
        raza = ask_choice("Selecciona la Especie/Raza a usar para todos los collares:", razas)
        compania = input("\nCompañía a usar para todos los collares (escribe el nombre): ").strip()
        red = ask_choice("Selecciona la Red a usar para todos los collares:", redes)
        print()
    elif action == "status":
        print("Acción: Ver estado (sólo seleccionar)\n")

    driver = build_driver(headless=not args.wb)
    try:
        if action == "create":
            run_create(driver, devices)
            driver.quit()
        elif action == "multicast":
            run_multicast(driver, devices, group_name)
            driver.quit()
        elif action == "pappstor":
            run_pappstor(driver, devices, raza, compania, red)
            driver.quit()
        elif action == "status":
            run_status(driver, devices)
            driver.quit()
    except Exception as exc:
        print(f"\nError inesperado: {exc}")
        driver.quit()
        raise


if __name__ == "__main__":
    main()
