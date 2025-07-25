USE dataset_fashion_store_products;

-- ----------------------------------------------------------------------------------------------------------------------------------
-- Identify and count the products in need of restocking
SELECT 
	EXTRACT(YEAR FROM si.sale_date) AS sale_year,
	category,
    SUM(quantity) as total_items_sold
FROM
	salesitems as si
JOIN products as p
ON p.product_id = si.product_id
GROUP BY category, sale_year
ORDER BY total_items_sold DESC;
-- dresses sold the most items in total followed by T-Shirts


-- ----------------------------------------------------------------------------------------------------------------------------------
-- Display the sales over time
-- Because there are only two months of data the running total of all months can be displayed in one chart and the months can be compared

CREATE OR REPLACE VIEW monthly_running_total AS 
	WITH RECURSIVE calendar AS (
	  SELECT DATE('2025-04-01') AS calendar_date
	  UNION ALL
	  SELECT DATE_ADD(calendar_date, INTERVAL 1 DAY)
	  FROM calendar
	  WHERE calendar_date <  DATE('2025-05-31')
	)
	SELECT 
		c.calendar_date,
		IFNULL(SUM(si.quantity), 0) AS daily_total,
		SUM(IFNULL(SUM(si.quantity), 0)) OVER (
		  PARTITION BY YEAR(c.calendar_date), MONTH(c.calendar_date)
		  ORDER BY c.calendar_date
		) AS running_total,
        IFNULL(SUM(si.discount_applied), 0) AS daily_discount_total
	FROM 
		calendar c
	LEFT JOIN sales s ON DATE(s.sale_date) = c.calendar_date
	LEFT JOIN salesitems si ON s.sale_id = si.sale_id
	GROUP BY c.calendar_date
	ORDER BY c.calendar_date;
    

    
-- ----------------------------------------------------------------------------------------------------------------------------------
-- is a shortage in the stock situation of the best selling product category foreseeable?
SELECT 
	category,
    SUM(stock_quantity) as total_stock
FROM
	products as p
JOIN stock as st
ON p.product_id = st.product_id
GROUP BY category
ORDER BY total_stock DESC;

-- what is the average orderbank reach of each product? 
-- i.e. for how many months is the stock sufficient (calculating with an average monthly sales)?
-- which products should be restocked? HOW many products need to be restocked?
-- criteria for restocking is that the orderbank reach is less than 2 months
CREATE OR REPLACE VIEW order_bank_reach AS
WITH avg_monthly_quantity AS (
	-- Calculate the average monthly quantity sold per product
	SELECT 
		product_id,
		ROUND(AVG(monthly_total), 2) AS avg_monthly_quantity
		FROM
		(
			-- Calculate total quantity sold per product for each month
			SELECT 
				product_id,
				DATE_FORMAT(s.sale_date, '%Y-%m') AS sale_month,
				SUM(si.quantity) AS monthly_total
			FROM 
				salesitems si
			JOIN sales s ON s.sale_id = si.sale_id
			GROUP BY 
				sale_month, product_id
			)AS monthly_data
	GROUP BY product_id
),

total_stock AS (
	-- Sum total stock quantity across warehouses (e.g., Germany and France)
	SELECT
		product_id,
		SUM(stock_quantity) as total_stock_quantity
	FROM
		stock
	GROUP BY product_id
),
order_bank_reach as (
 -- Calculate how many months the current stock can cover based on average monthly sales
	SELECT 
		st.product_id,
        avg_monthly_quantity.avg_monthly_quantity,
        st.total_stock_quantity,
		total_stock_quantity / avg_monthly_quantity as order_bank_reach
	FROM avg_monthly_quantity
	JOIN total_stock as st
	ON st.product_id = avg_monthly_quantity.product_id
	-- WHERE total_stock_quantity / avg_monthly_quantity  < 2
	ORDER BY total_stock_quantity / avg_monthly_quantity  ASC
)
-- Final selection joining product details
select order_bank_reach.avg_monthly_quantity,
       order_bank_reach.total_stock_quantity,
       order_bank_reach.order_bank_reach,
       p.*
FROM order_bank_reach
JOIN products as p
ON p.product_id = order_bank_reach.product_id;


-- ----------------------------------------------------------------------------------------------------------------------------------
-- Identify the items with a high order bank reach and high margins in order to be included in the next sales campaign 
-- The Items should have an orderbank reach of 1.5 the average of the category and after a discount of 10% still have an above average margin for their category

CREATE OR REPLACE VIEW products_for_next_sales_campain_high_proft AS
	WITH product_margins AS (
		-- Add margin and discounted margin to the orderbank reach view
		SELECT 
			*,
			ROUND((catalog_price - cost_price) / catalog_price, 2) AS margin,
			ROUND(((catalog_price * 0.90) - cost_price) / (catalog_price * 0.90), 2) AS discounted_margin -- 10 % discount
		FROM 
			order_bank_reach
	),
	category_avg_margins AS (
		-- calculate the average margin of each category
		SELECT
			category,
			ROUND(AVG(margin), 2) AS category_avg_margin
		FROM product_margins
		GROUP BY category
	),
	category_avg_obr AS (
		-- calculate the average Order Bank reach of each category
		SELECT 
			category,
			AVG(order_bank_reach) as category_avg_obr
		FROM order_bank_reach
		GROUP BY category
	)
	SELECT 
		pm.*, 
		cam.category_avg_margin,
		cao.category_avg_obr
	FROM product_margins pm
	JOIN category_avg_margins cam
	  ON pm.category = cam.category
	JOIN category_avg_obr cao
	  ON cao.category = pm.category
	WHERE pm.discounted_margin > cam.category_avg_margin 
	  AND cao.category_avg_obr < pm.order_bank_reach;

-- ----------------------------------------------------------------------------------------------------------------------------------
-- Are there any products in stock with above average orderbank reach (2,5 x avg of category)?
CREATE OR REPLACE VIEW products_for_next_sales_campain_high_stock AS
	WITH category_avg_obr AS (
		-- calculate the average Order Bank reach of each category
		SELECT 
			category,
			AVG(order_bank_reach) as category_avg_obr
		FROM order_bank_reach
		GROUP BY category
	)
	SELECT 
		obr.*, 		
		cao.category_avg_obr
	FROM order_bank_reach obr	
	JOIN category_avg_obr cao
	  ON cao.category = obr.category
	WHERE 2.5 * cao.category_avg_obr < obr.order_bank_reach;

-- ----------------------------------------------------------------------------------------------------------------------------------
-- Identify the most effective sales channel to be focused in the next campaign
-- i.e. the Channel with the highest amount of sales
    
SELECT 
   channel_campaigns,
   ROUND(SUM(item_total),2) as total_revenue,
   SUM(quantity) as total_units_sold
FROM 
	dataset_fashion_store.salesitems as si
GROUP BY channel_campaigns
ORDER BY total_revenue DESC;

-- ----------------------------------------------------------------------------------------------------------------------------------
-- Identify VIP customers that generate above average (x1,5) revenue 
CREATE OR REPLACE VIEW VIP_customers AS 
	WITH total_of_customer AS (
		SELECT 
			c.customer_id,
			-- c.age_range,
			-- s.sale_id,
			ROUND(SUM(s.total_amount),2) total_of_customer
		FROM 
			customers as c
		JOIN sales as s
		ON c.customer_id = s.customer_id
		GROUP BY  c.customer_id
		),
	-- AVG of customer: '559.03'    
	above_avg_customers AS (
		SELECT 
			*
		FROM 
			total_of_customer
		WHERE 
			total_of_customer > 1.5 * (
				SELECT
					ROUND(AVG(total_of_customer), 2) as avg_customer_spending
				FROM
				total_of_customer
			)
		ORDER BY total_of_customer.total_of_customer DESC
		)
	SELECT
		above_avg_customers.total_of_customer,
		c.*
	FROM 
		above_avg_customers
	JOIN customers as c
	ON c.customer_id = above_avg_customers.customer_id;
    
    
-- ----------------------------------------------------------------------------------------------------------------------------------
-- Identify the age range that most customers belong to in order to adjust the language used in the next sales campaign - go by revenue created
-- (serious for older people and fun and energetic for younger audiences)
CREATE VIEW age_ranges_with_revenue AS 
	SELECT 
		age_range,
		COUNT(DISTINCT(c.customer_id)) as customer_count,
		ROUND(SUM(total_amount), 2) as total_revenue
	FROM 
		customers as c
	JOIN 
		sales as s
	ON s.customer_id = c.customer_id
	GROUP BY age_range
	ORDER BY total_revenue DESC;
    
    
    
-- ----------------------------------------------------------------------------------------------------------------------------------  
-- Determine stock value / sunk cost
CREATE OR REPLACE VIEW stock_value AS
	SELECT 
		gender,
		country,
		ROUND(SUM(catalog_price * stock_quantity), 2) as total_stock_value,
		ROUND(SUM(cost_price * stock_quantity), 2) as total_sunk_cost,
		ROUND(AVG(stock_quantity), 2) as avg_quantity
	FROM 
		stock as st
	LEFT JOIN products as p
	ON p.product_id = st.product_id
	GROUP BY country, gender;




-- ----------------------------------------------------------------------------------------------------------------------------------  
-- What percentage of our registered users are active?
CREATE OR REPLACE VIEW percentage_active_customers AS 
	SELECT
		COUNT(DISTINCT(c.customer_id)) as total_customers,
		COUNT(DISTINCT CASE WHEN sale_id IS NULL THEN c.customer_id END) as inactive_customers,
		COUNT(DISTINCT CASE WHEN sale_id IS NOT NULL THEN c.customer_id END) as active_customers,
		COUNT(DISTINCT CASE WHEN sale_id IS NOT NULL THEN c.customer_id END)  / COUNT(DISTINCT(c.customer_id)) as percentage_active_customers
	FROM customers as c 
	LEFT JOIN sales as s
	ON c.customer_id = s.customer_id;
    
-- ----------------------------------------------------------------------------------------------------------------------------------  
-- Find the total percentage of revenue by customers who are in 95th percentile by spendings compared to all revenue
CREATE OR REPLACE VIEW revenue_top_5_spenders AS 
	WITH customer_percentiles AS (
		SELECT
			 s.customer_id,
			 sum(total_amount) as total_amount,
			 PERCENT_RANK() OVER (ORDER BY sum(total_amount) ) AS pct_rank
		FROM
			customers as c
		JOIN 
			sales as s
		ON s.customer_id = c.customer_id
		GROUP BY s.customer_id
		)
	SELECT 
		"customer_id" as percentile_source, 
		ROUND(SUM(total_amount), 2)  as total_revenue,
		ROUND(SUM(CASE WHEN pct_rank >= 0.95 THEN total_amount END), 2) AS revenue_top_5_percentile,
		ROUND(SUM(CASE WHEN pct_rank < 0.95 THEN total_amount END), 2)  as revenue_lower_95_percentle,
		ROUND(SUM(CASE WHEN pct_rank >= 0.95 THEN total_amount END) / SUM(total_amount), 2) as top_5_of_total
	 FROM customer_percentiles;
     
-- ----------------------------------------------------------------------------------------------------------------------------------   
-- The same for products or brands — do we have have top products/brands and the rest aren’t selling much
-- There is only one brand in the data: 'Tiva' so I will focus on product_id
SELECT
	DISTINCT(brand)
FROM
	products;
    
CREATE OR REPLACE VIEW revenue_top_5_products AS 
	WITH product_percentile AS (
		SELECT
			p.product_id,
			sum(si.item_total) as total_amount,
			PERCENT_RANK() OVER (ORDER BY  sum(si.item_total)  ) AS pct_rank
		FROM 
			salesitems as si
		JOIN products as p
		ON p.product_id = si.product_id
		GROUP BY p.product_id
		)
	SELECT 
	"product_id" as percentile_source, 
		ROUND(SUM(total_amount), 2)  as total_revenue,
		ROUND(SUM(CASE WHEN pct_rank >= 0.95 THEN total_amount END), 2) AS revenue_top_5_percentile,
		ROUND(SUM(CASE WHEN pct_rank < 0.95 THEN total_amount END), 2)  as revenue_lower_95_percentle,
		ROUND(SUM(CASE WHEN pct_rank >= 0.95 THEN total_amount END) / SUM(total_amount), 2) as top_5_of_total
	 FROM product_percentile;

-- On you diagram ‘Display the sales over time’ you can see that there are 2 monhts 
-- with and without discounts after 13th. 
-- The question is — was it worth it to have discounts 
-- did we get more money than we discounted ove the course of 13-31
WITH may_sale AS (
	SELECT		
        si.*,
		ROUND(catalog_price - cost_price, 2) as profit_before_discount,
		ROUND((catalog_price - discount_applied) - cost_price, 2)  as profit_after_discount,
		CASE 
			WHEN si.sale_date BETWEEN DATE("2025-04-13") AND DATE("2025-04-20")  THEN "April reference during"
            WHEN si.sale_date BETWEEN DATE("2025-04-21") AND DATE("2025-04-30")  THEN "April reference after"
            WHEN si.sale_date BETWEEN DATE("2025-05-01") AND DATE("2025-05-12") THEN "Before May Sale"
            WHEN si.sale_date BETWEEN DATE("2025-05-13") AND DATE("2025-05-20") THEN "During May Sale"
            WHEN si.sale_date BETWEEN DATE("2025-05-21") AND DATE("2025-05-31")  THEN "After May Sale"			
            WHEN si.sale_date BETWEEN DATE("2025-06-01") AND DATE("2025-06-31") THEN "June"
		END as sale_bin,
        CASE 			
            WHEN si.sale_date BETWEEN DATE("2025-05-01") AND DATE("2025-05-12") THEN 1
            WHEN si.sale_date BETWEEN DATE("2025-05-13") AND DATE("2025-05-20") THEN 2
            WHEN si.sale_date BETWEEN DATE("2025-04-13") AND DATE("2025-04-20")  THEN 3
            WHEN si.sale_date BETWEEN DATE("2025-05-21") AND DATE("2025-05-31")  THEN 4	
            WHEN si.sale_date BETWEEN DATE("2025-06-01") AND DATE("2025-06-31") THEN 5
            WHEN si.sale_date BETWEEN DATE("2025-04-21") AND DATE("2025-04-30")  THEN 6
		END as sale_bin_nr
	FROM 
		products as p
	JOIN salesitems as si
	ON p.product_id = si.product_id
)
SELECT
	sale_bin_nr,
	sale_bin,
	ROUND(SUM(discount_applied), 2) as sum_discount_applied,
    ROUND(SUM(profit_after_discount), 2) as sum_profit_after_discount
FROM
	may_sale
WHERE sale_bin = 'Before May Sale' OR sale_bin = 'After May Sale' or sale_bin = 'During May Sale' 
or sale_bin =  "April reference during" or sale_bin = "April reference after"
GROUP BY 
    sale_bin, sale_bin_nr
ORDER BY sale_bin_nr

