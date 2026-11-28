"""Exercise the real upload controls against localhost synthetic data only."""
from pathlib import Path
from tempfile import TemporaryDirectory
from openpyxl import Workbook
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.common.keys import Keys
from selenium.webdriver.support.ui import WebDriverWait
from demo_server import HEADERS

options=webdriver.ChromeOptions(); options.add_argument('--headless=new'); options.add_argument('--disable-dev-shm-usage')
with TemporaryDirectory() as work, webdriver.Chrome(options=options) as browser:
    wb=Workbook(); ws=wb.active; ws.append(HEADERS); ws.append(['42','2022','1','SA','20220131','4000','NEW','BEBAN']); path=Path(work)/'fixture.xlsx'; wb.save(path)
    browser.get('http://127.0.0.1:8080/'); wait=WebDriverWait(browser,90)
    try:
        field=wait.until(lambda d:d.find_element(By.CSS_SELECTOR,"input[id$='company-inner']")); field.send_keys('DEMO',Keys.TAB)
        def button(text):return browser.find_element(By.XPATH,"//button[normalize-space(.)='"+text+"']")
        browser.find_element(By.CSS_SELECTOR,'input[type=file]').send_keys(str(path))
        wait.until(lambda _:button('Validate workbook').is_enabled());button('Validate workbook').click()
        def planned(_):
            if 'PLANNED' in browser.find_element(By.TAG_NAME,'body').text:return True
            if button('Refresh status').is_enabled():button('Refresh status').click()
            return False
        wait.until(planned); assert not button('Apply Changes').is_enabled();print('Rendered page, uploaded genuine XLSX, displayed PLANNED row, Apply disabled.')
    except Exception:
        print('Page text:',repr(browser.find_element(By.TAG_NAME,'body').text[:1500]));print('Browser console:',browser.get_log('browser')[-6:]);raise
