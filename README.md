# political-scorecard-node


### Political-Scorecard-Backend
## To run the test backend build and generate code coverage report
sudo docker compose -f docker-compose-test.yml up --build

## To copy the report to an area outside the volume so it can be viewed

cp -r ./target/site/jacoco ./jacoco-report
then go to jacoco-report/jacoco, and right click, and open the files browser.
In the files browser, in the jacoco folder, go to the bottom and double click index.html
a window should pop up for your default browser and you can go to it to see the
code coverage report.