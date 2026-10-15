"""Tests for choosing the assignee (acceptance criteria of the automatic assignment)."""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from team import elegir  # noqa: E402

ANA = {"login": "ana", "areas": ["area:api"], "active": True}
BRUNO = {"login": "bruno", "areas": ["area:api", "area:infra"], "active": True}
CARLA = {"login": "carla", "areas": ["area:docs"], "active": True}
DANI = {"login": "dani", "areas": ["area:api"], "active": False}


class Elegir(unittest.TestCase):
    def test_asigna_a_quien_cubre_el_area(self):
        self.assertEqual(elegir([ANA, CARLA], ["type:bug", "area:docs"], {}), "carla")

    def test_entre_varios_del_area_gana_el_de_menos_carga(self):
        self.assertEqual(elegir([ANA, BRUNO], ["area:api"], {"ana": 3, "bruno": 1}), "bruno")

    def test_sin_nadie_del_area_va_al_de_menos_carga(self):
        self.assertEqual(elegir([ANA, CARLA], ["area:infra"], {"ana": 2, "carla": 0}), "carla")

    def test_sin_area_en_el_issue_va_al_de_menos_carga(self):
        self.assertEqual(elegir([ANA, BRUNO], ["type:task"], {"ana": 0, "bruno": 4}), "ana")

    def test_ignora_inactivos(self):
        self.assertEqual(elegir([DANI, CARLA], ["area:api"], {"dani": 0, "carla": 5}), "carla")

    def test_sin_integrantes_activos_no_asigna(self):
        self.assertIsNone(elegir([DANI], ["area:api"], {}))
        self.assertIsNone(elegir([], ["area:api"], {}))

    def test_empate_se_resuelve_por_orden_del_archivo(self):
        self.assertEqual(elegir([BRUNO, ANA], ["area:api"], {}), "bruno")


if __name__ == "__main__":
    unittest.main()
