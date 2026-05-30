-- =====================================================
-- FOOD DELIVERY ANALYTICS PROJECT
-- Swiggy/Zomato Operational Analysis
-- Author: Neethu Raj
-- Tools Used: MySQL
-- =====================================================

-- =====================================================
-- Project Objective:
-- Analyze food delivery operations data to evaluate rider efficiency,
-- delivery performance, cancellation behavior, peak-hour trends,
-- and distance-based operational challenges using MySQL.
-- =====================================================



-- =====================================================
-- STEP 1: CREATE DATABASE
-- =====================================================

CREATE DATABASE food_delivery;

USE food_delivery;


-- =====================================================
-- STEP 2: LOAD CSV DATA
-- =====================================================

-- Load CSV file using the MySQL Workbench import wizard.
-- Since the dataset is large, cancel after partial loading
-- so the table structure gets created automatically.

-- Remove previously loaded records while retaining table structure

TRUNCATE swiggy_zomato_order_info;


-- Import CSV File

LOAD DATA LOCAL INFILE 
"C:/Users/user/Desktop/Data analyst/Portfolio/Swiggy Zomato Order Information.csv"

INTO TABLE swiggy_zomato_order_info

FIELDS TERMINATED BY ',' 
ENCLOSED BY '"'
LINES TERMINATED BY '\n'

IGNORE 1 ROWS;


-- Verify Data

SELECT *
FROM swiggy_zomato_order_info
LIMIT 10;


-- =====================================================
-- STEP 3: DATA CLEANING
-- =====================================================


-- -----------------------------------------------------
-- Convert TEXT Columns to DATETIME Format
-- -----------------------------------------------------

UPDATE swiggy_zomato_order_info

SET order_time = STR_TO_DATE(NULLIF(order_time, ""), '%Y-%m-%d %H:%i:%s'),
    order_date = STR_TO_DATE(NULLIF(order_date, ""), '%d-%m-%Y'),
    allot_time = STR_TO_DATE(NULLIF(allot_time, ""), '%Y-%m-%d %H:%i:%s'),
    accept_time = STR_TO_DATE(NULLIF(accept_time, ""), '%d-%m-%Y %H:%i'),
    pickup_time = STR_TO_DATE(NULLIF(pickup_time, ""), '%d-%m-%Y %H:%i'),
    delivered_time = STR_TO_DATE(NULLIF(delivered_time, ""), '%d-%m-%Y %H:%i');

UPDATE swiggy_zomato_order_info

SET cancelled_time = CASE
    WHEN LENGTH(TRIM(cancelled_time)) < 10 THEN NULL

    ELSE STR_TO_DATE(TRIM(cancelled_time), '%d-%m-%Y %H:%i')

END;


ALTER TABLE swiggy_zomato_order_info

MODIFY COLUMN order_time DATETIME,
MODIFY COLUMN delivered_time DATETIME,
MODIFY COLUMN order_date DATE,
MODIFY COLUMN allot_time DATETIME,
MODIFY COLUMN accept_time DATETIME,
MODIFY COLUMN pickup_time DATETIME,
MODIFY COLUMN cancelled_time DATETIME;


-- -----------------------------------------------------
-- Remove Duplicate Records
-- -----------------------------------------------------

ALTER TABLE swiggy_zomato_order_info

ADD COLUMN id INT AUTO_INCREMENT PRIMARY KEY FIRST;


DELETE FROM swiggy_zomato_order_info

WHERE id IN (

    SELECT id

    FROM (

        SELECT id,

               ROW_NUMBER() OVER (
                   PARTITION BY order_id
                   ORDER BY id ASC
               ) AS row_num

        FROM swiggy_zomato_order_info

    ) t

    WHERE row_num > 1
);


-- -----------------------------------------------------
-- Handle Missing Values
-- -----------------------------------------------------

DELETE FROM swiggy_zomato_order_info

WHERE order_time IS NULL;


-- =====================================================
-- STEP 4: FEATURE ENGINEERING
-- =====================================================


-- -----------------------------------------------------
-- Create Delivery Duration Column
-- -----------------------------------------------------

ALTER TABLE swiggy_zomato_order_info

ADD delivery_minutes INT;


UPDATE swiggy_zomato_order_info

SET delivery_minutes =
TIMESTAMPDIFF(MINUTE, allot_time, delivered_time);


-- -----------------------------------------------------
-- Create Order Hour Column
-- -----------------------------------------------------

ALTER TABLE swiggy_zomato_order_info

ADD order_hour INT;


UPDATE swiggy_zomato_order_info

SET order_hour = HOUR(order_time);


-- -----------------------------------------------------
-- Create Ride Distance Column
-- -----------------------------------------------------

ALTER TABLE swiggy_zomato_order_info

ADD ride_distance FLOAT;


UPDATE swiggy_zomato_order_info

SET ride_distance =
first_mile_distance + last_mile_distance;


-- =====================================================
-- STEP 5: RIDER PERFORMANCE ANALYSIS
-- =====================================================


-- -----------------------------------------------------
-- Create Rider Efficiency Table
-- -----------------------------------------------------

CREATE TABLE rider_efficiency AS

WITH riders AS (

    SELECT

        rider_id,

        COUNT(*) AS total_orders,

        SUM(
            CASE
                WHEN delivered_time IS NOT NULL THEN 1
                ELSE 0
            END
        ) AS delivered_orders,

        SUM(cancelled) AS total_cancelled,

        ROUND(
            AVG(
                CASE
                    WHEN delivered_time IS NOT NULL
                    THEN delivery_minutes
                END
            ),
            2
        ) AS avg_delivery_time,

        ROUND(
            SUM(cancelled) * 100.0 / COUNT(*),
            2
        ) AS cancellation_rate

    FROM swiggy_zomato_order_info

    GROUP BY rider_id
)

SELECT
    rider_id,
    total_orders,
    delivered_orders,
    total_cancelled,
    avg_delivery_time,
    cancellation_rate,

    CASE

        WHEN avg_delivery_time IS NULL
        THEN 'No Delivery'

        WHEN avg_delivery_time <= 20
             AND cancellation_rate < 5
        THEN 'Top Performer'

        WHEN avg_delivery_time <= 30
        THEN 'Average Performer'

        ELSE 'Poor Performer'

    END AS rider_category

FROM riders;


SELECT *
FROM rider_efficiency
ORDER BY rider_id;



-- -----------------------------------------------------
-- Top 10 Riders Analysis
-- -----------------------------------------------------

-- -----------------------------------------------------
--  Identify riders with consistently fast delivery
--  and low cancellation rates
-- -----------------------------------------------------

CREATE TABLE top_riders AS
SELECT *
FROM (
    SELECT 
        rider_id,
        DENSE_RANK() OVER (
            ORDER BY avg_delivery_time ASC, cancellation_rate ASC
        ) AS rider_rank,
        total_orders,
        avg_delivery_time,
        total_cancelled,
        cancellation_rate
    FROM rider_efficiency
    WHERE rider_category = 'Top Performer'
      AND total_orders >= 10   -- reliability filter
) ranked
ORDER BY rider_rank
LIMIT 10;

SELECT * 
FROM top_riders;


-- -----------------------------------------------------
-- Worst Rider Analysis
-- -----------------------------------------------------

CREATE TABLE worst_riders AS

SELECT *
FROM rider_efficiency

WHERE avg_delivery_time > 30
      AND total_orders >= 10
      AND cancellation_rate > 10
      
ORDER BY avg_delivery_time DESC, cancellation_rate DESC;

SELECT * 
FROM worst_riders 
LIMIT 10;

-- -----------------------------------------------------
-- Inactive Rider Analysis
-- -----------------------------------------------------

CREATE TABLE inactive_riders AS

SELECT rider_id,
       COUNT(*) AS total_orders,
       SUM(CASE 
           WHEN delivered_time IS NOT NULL THEN 1 
           ELSE 0 
       END) AS delivered_orders,
       SUM(cancelled) AS total_cancelled
       
FROM swiggy_zomato_order_info

GROUP BY rider_id

HAVING delivered_orders = 0;

SELECT * 
FROM inactive_riders;


-- -----------------------------------------------------
-- Fastest Rider Analysis
-- -----------------------------------------------------

SELECT rider_id,
       avg_delivery_time,
       delivered_orders
FROM rider_efficiency
WHERE avg_delivery_time IS NOT NULL
  AND delivered_orders >= 10
ORDER BY avg_delivery_time ASC, delivered_orders DESC
LIMIT 10;


-- =====================================================
-- STEP 6: LATE DELIVERY ANALYSIS
-- =====================================================


-- -----------------------------------------------------
-- Rider Late Delivery Percentage
-- -----------------------------------------------------

WITH late_deliveries AS (
	SELECT rider_id,
       SUM(CASE 
            WHEN delivered_time IS NOT NULL THEN 1 
            ELSE 0 
        END) AS delivered_orders,
	   SUM(CASE 
			 WHEN delivery_minutes > 30 AND delivered_time IS NOT NULL THEN 1
             ELSE 0
			END) AS late_orders
	FROM swiggy_zomato_order_info
	GROUP BY rider_id
),
late_metrics AS (
    SELECT 
        rider_id,
        delivered_orders,
        late_orders,
        ROUND((late_orders * 1.0 / delivered_orders) * 100, 2) 
            AS late_delivery_percentage
    FROM late_deliveries
    WHERE delivered_orders > 10
)
SELECT 
    rider_id,
    delivered_orders,
    late_orders,
    late_delivery_percentage,
    RANK() OVER (ORDER BY late_delivery_percentage DESC) AS late_delivery_rank
FROM late_metrics
ORDER BY late_delivery_percentage DESC;


-- =====================================================
-- STEP 7: RIDER PRODUCTIVITY ANALYSIS
-- =====================================================


-- -----------------------------------------------------
-- Orders Per Rider Per Day
-- -----------------------------------------------------

SELECT rider_id,
	   order_date,
       COUNT(*) AS total_orders
FROM swiggy_zomato_order_info
GROUP BY rider_id, order_date
ORDER BY rider_id, order_date;


-- -----------------------------------------------------
-- Average Daily Orders Per Rider
-- -----------------------------------------------------

SELECT rider_id,
	   ROUND(
		    COUNT(*) * 1.0/
		    COUNT(DISTINCT order_date),
		    2
	   ) AS avg_daily_orders
FROM swiggy_zomato_order_info
GROUP BY rider_id
HAVING COUNT(*) >= 10
ORDER BY avg_daily_orders DESC;

-- =====================================================
-- STEP 8: DISTANCE-BASED DELIVERY ANALYSIS
-- =====================================================


-- -----------------------------------------------------
-- Distance vs Delivery Performance
-- -----------------------------------------------------

-- -----------------------------------------------------
-- Analyze whether longer delivery distances
-- increase late delivery rates
-- -----------------------------------------------------

WITH order_distance AS (
    SELECT
        CASE
            WHEN ride_distance >= 0  AND ride_distance < 2  THEN '0-2 km'
            WHEN ride_distance >= 2  AND ride_distance < 5  THEN '2-5 km'
            WHEN ride_distance >= 5  AND ride_distance < 8  THEN '5-8 km'
            WHEN ride_distance >= 8  AND ride_distance < 15 THEN '8-15 km'
            ELSE '15+ km'
        END AS distance_group,
        delivered_time,
        delivery_minutes
    FROM swiggy_zomato_order_info
),

distance_summary AS (
    SELECT
        distance_group,
		
        COUNT(*) AS total_orders,

        SUM(CASE
                WHEN delivered_time IS NOT NULL THEN 1
                ELSE 0
            END) AS delivered_orders,

        SUM(CASE
                WHEN delivery_minutes > 30
                     AND delivered_time IS NOT NULL
                THEN 1
                ELSE 0
            END) AS late_orders,

        ROUND(
            AVG(CASE 
                WHEN delivered_time IS NOT NULL 
                THEN delivery_minutes 
            END), 2
        ) AS avg_delivery_time

    FROM order_distance
    GROUP BY distance_group
)

SELECT
    distance_group,
    total_orders,
    delivered_orders,
    avg_delivery_time,

    ROUND(
        (late_orders * 1.0 / delivered_orders) * 100,
        2
    ) AS late_delivery_percentage

FROM distance_summary 
ORDER BY 
	CASE
		WHEN distance_group = '0-2 km' THEN 1
        WHEN distance_group = '2-5 km' THEN 2
        WHEN distance_group = '5-8 km' THEN 3
        WHEN distance_group = '8-15 km' THEN 4
        ELSE 5
	END;
    


-- =====================================================
-- STEP 9: LONG-DISTANCE RIDER ANALYSIS
-- =====================================================


-- -----------------------------------------------------
-- Long Distance Rider Performance
-- -----------------------------------------------------

CREATE TABLE long_distance_rider_performance AS
WITH long_distance AS (
	SELECT 
		rider_id,
		ROUND(
            AVG(CASE 
                WHEN delivered_time IS NOT NULL 
                THEN delivery_minutes 
            END), 2
        ) AS avg_delivery_time,
		SUM(CASE
                WHEN delivered_time IS NOT NULL THEN 1
                ELSE 0
		END) AS delivered_orders,

		SUM(CASE
                WHEN delivery_minutes > 30
                     AND delivered_time IS NOT NULL
                THEN 1
                ELSE 0
            END) AS late_orders
FROM swiggy_zomato_order_info
WHERE ride_distance > 8
GROUP BY rider_id
)
SELECT rider_id,
       delivered_orders,
	   late_orders,
       avg_delivery_time,
       ROUND(
        (late_orders * 1.0 / delivered_orders) * 100,
        2
        ) AS late_delivery_percentage
FROM long_distance
WHERE delivered_orders > 10;

SELECT * 
FROM long_distance_rider_performance;


-- -----------------------------------------------------
-- Best Long-Distance Riders
-- -----------------------------------------------------

SELECT
       rider_id,
       delivered_orders,
       late_orders,
       avg_delivery_time,
       late_delivery_percentage,

       DENSE_RANK() OVER(
            ORDER BY avg_delivery_time ASC,
                     late_delivery_percentage ASC,
                     delivered_orders DESC
       ) AS best_rider_rank

FROM long_distance_rider_performance

WHERE delivered_orders >= 15
      AND late_delivery_percentage < 40

ORDER BY best_rider_rank
LIMIT 10;



-- -----------------------------------------------------
-- Worst Long-Distance Riders
-- -----------------------------------------------------

SELECT
       rider_id,
       delivered_orders,
       late_orders,
       avg_delivery_time,
       late_delivery_percentage,

       DENSE_RANK() OVER(
            ORDER BY late_delivery_percentage DESC,
                     avg_delivery_time DESC,
                     delivered_orders DESC
       ) AS worst_rider_rank

FROM long_distance_rider_performance

WHERE delivered_orders >= 15
      AND late_delivery_percentage > 60

ORDER BY worst_rider_rank
LIMIT 10;


-- =====================================================
-- STEP 10: PEAK HOUR PERFORMANCE ANALYSIS
-- =====================================================


-- -----------------------------------------------------
-- Analyze the Impact of Peak Hours
-- on Delivery Performance
-- -----------------------------------------------------

CREATE TABLE order_hour_performance AS
	WITH order_hour_table AS ( 
		SELECT 
			order_hour,
			COUNT(*) AS total_orders,
			SUM(CASE
				WHEN delivered_time IS NOT NULL THEN 1 
				ELSE 0 
			END) AS delivered_orders,

			SUM(cancelled) AS total_cancelled,
			ROUND(
				SUM(cancelled) * 100.0 / COUNT(*), 2
					) AS cancellation_rate,
			SUM(CASE
					WHEN delivery_minutes > 30
						AND delivered_time IS NOT NULL
					THEN 1
					ELSE 0
				END) AS late_orders,

			ROUND(
				AVG(CASE 
						WHEN delivered_time IS NOT NULL 
						THEN delivery_minutes 
					END), 2
				) AS avg_delivery_time
        
		FROM swiggy_zomato_order_info
		GROUP BY order_hour
)
SELECT 
	   order_hour,
	   total_orders,
	   delivered_orders,
       total_cancelled,
       cancellation_rate,
       late_orders,
       avg_delivery_time,
       ROUND(
        (late_orders * 1.0 / delivered_orders) * 100,
        2
        ) 
AS late_delivery_percentage
FROM order_hour_table;



SELECT *
FROM order_hour_performance
ORDER BY total_orders DESC;


-- =====================================================
-- FINAL VALIDATION QUERIES
-- =====================================================

SELECT *
FROM swiggy_zomato_order_info;


SELECT COUNT(DISTINCT order_id)
FROM swiggy_zomato_order_info
WHERE order_id IS NOT NULL;

-- =====================================================
-- END OF PROJECT
-- =====================================================
