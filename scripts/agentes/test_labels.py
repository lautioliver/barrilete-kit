"""Tests de la combinación de labels: instalar en un repo existente no borra sus labels (#121)."""
import os
import re
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from labels import combinar  # noqa: E402

KIT = '''# cabecera
- name: "tipo:bug"
  color: "7B61FF"
  description: "Algo no funciona"
- name: "logica-negocio"
  color: "000000"
  description: "Regla de negocio"
'''


def nombres(texto):
    return re.findall(r'^- name: "(.*)"$', texto, re.M)


def bloque(texto, nombre):
    m = re.search(r'^- name: "%s"\n  color: "(.*)"\n  description: "(.*)"' % re.escape(nombre), texto, re.M)
    return m.groups() if m else None


class Combinar(unittest.TestCase):
    def test_agrega_los_labels_del_repo_con_color_y_descripcion(self):
        r = combinar(KIT, [{"name": "bug", "color": "d73a4a", "description": "Algo falla"}])
        self.assertEqual(bloque(r, "bug"), ("D73A4A", "Algo falla"))
        self.assertIn("tipo:bug", nombres(r))

    def test_los_propios_van_en_una_seccion_marcada(self):
        r = combinar(KIT, [{"name": "bug", "color": "d73a4a", "description": ""}])
        self.assertIn("propios del proyecto", r.split('- name: "bug"')[0].splitlines()[-1])

    def test_no_duplica_nombres(self):
        r = combinar(KIT, [{"name": "bug", "color": "111111", "description": ""},
                           {"name": "tipo:bug", "color": "222222", "description": "x"}])
        n = [x.lower() for x in nombres(r)]
        self.assertEqual(len(n), len(set(n)))

    def test_mismo_nombre_que_el_kit_conserva_el_color_del_repo(self):
        r = combinar(KIT, [{"name": "tipo:bug", "color": "ff0000", "description": "mía"}])
        self.assertEqual(bloque(r, "tipo:bug")[0], "FF0000")
        self.assertEqual(nombres(r).count("tipo:bug"), 1)

    def test_mismo_nombre_ignora_mayusculas(self):
        r = combinar(KIT, [{"name": "Logica-Negocio", "color": "abcdef", "description": ""}])
        self.assertEqual(bloque(r, "logica-negocio")[0], "ABCDEF")
        self.assertEqual(len(nombres(r)), 2)

    def test_es_idempotente(self):
        ex = [{"name": "bug", "color": "d73a4a", "description": "Falla"}]
        una = combinar(KIT, ex)
        self.assertEqual(combinar(una, ex), una)

    def test_descripcion_con_comillas_queda_valida(self):
        r = combinar(KIT, [{"name": "a", "color": "ffffff", "description": 'dice "hola"'}])
        self.assertIn(r'description: "dice \"hola\""', r)

    def test_descripcion_nula(self):
        r = combinar(KIT, [{"name": "a", "color": "ffffff", "description": None}])
        self.assertEqual(bloque(r, "a"), ("FFFFFF", ""))

    def test_sin_labels_existentes_deja_el_kit(self):
        self.assertEqual(combinar(KIT, []), KIT)


if __name__ == "__main__":
    unittest.main()
