import re
import time
import requests
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.common.exceptions import TimeoutException, WebDriverException
from selenium.common.exceptions import NoSuchElementException
from selenium.webdriver.edge.service import Service

def get_gradio_version_selenium(url):
    try:
        # Set up Selenium with Chrome in headless mode
        options = webdriver.EdgeOptions()
        options.add_argument("--headless")  # No browser UI
        options.add_argument("--no-sandbox")
        # options.add_argument("--disable-dev-shm-usage")
        options.binary_location = "/usr/bin/microsoft-edge"
        webdriver_service = Service("/home/zyd/course/cs528/cs528-project/msedgedriver")  # Path to your Edge WebDriver
        driver = webdriver.Edge(options=options, service=webdriver_service)
        
        driver.get(url)
        
        # element = WebDriverWait(driver, 15).until(
        #     EC.presence_of_element_located((By.CSS_SELECTOR, "div[class*='gradio-container']"))
        # )

        # driver.implicitly_wait(10)  # Implicit wait for elements to load
        time.sleep(5)  # Wait for the page to load
        driver.switch_to.frame(0)
        element = driver.find_element(By.CLASS_NAME, "gradio-container")
        # element = driver.find_element(By.TAG_NAME, "body")
        # print(element.get_attribute("innerHTML"))  # Print the inner HTML for debugging
        # input()
        
        # Get the class attribute
        class_attribute = element.get_attribute("class")
        
        # Extract the version number using regex (e.g., from "gradio-container-4-39-0")
        match = re.search(r'gradio-container-(\d+-\d+-\d+)', class_attribute)
        if match:
            # Convert "4-39-0" to "4.39.0"
            version = match.group(1).replace('-', '.')
            return version
        else:
            return -1
    
    except NoSuchElementException:
        print("Element not found")
        return -1
    except WebDriverException as e:
        print(f"WebDriver error: {str(e)}")
        return -1
    except Exception as e:
        return -1
    finally:
        driver.quit()  

def find_gradio_apps():
    # API endpoint for Hugging Face Spaces
    url = "https://huggingface.co/api/spaces"
    
    response = requests.get(url)
    response.raise_for_status()  
    
    spaces = response.json()
    
    gradio_apps = [space for space in spaces if space.get("sdk") == "gradio"]
    
    return gradio_apps

# Example usage
if __name__ == "__main__":
    
    file = open("output.csv", "w")
    for app in find_gradio_apps():
        url = f"https://huggingface.co/spaces/{app['id']}"
        version = get_gradio_version_selenium(url)
        print(f"- {url}: {version}")
        file.write(f"{url},{version}\n")