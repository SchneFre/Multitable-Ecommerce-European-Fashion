USE dataset_fashion_store;

ALTER TABLE customers
ADD CONSTRAINT PK_customer_id PRIMARY KEY (customer_id);

ALTER TABLE campaigns
ADD CONSTRAINT PK_campaign_id PRIMARY KEY (campaign_id);

ALTER TABLE products
ADD CONSTRAINT PK_product_id PRIMARY KEY (product_id);

ALTER TABLE sales
ADD CONSTRAINT PK_sale_id PRIMARY KEY (sale_id);

ALTER TABLE sales 
ADD CONSTRAINT FK_customer FOREIGN KEY (customer_id) REFERENCES customers(customer_id);

ALTER TABLE stock
ADD CONSTRAINT FK_product FOREIGN KEY (product_id) REFERENCES products(product_id);

ALTER TABLE salesitems 
ADD CONSTRAINT FK_sale_id FOREIGN KEY (sale_id) REFERENCES sales(sale_id);

ALTER TABLE salesitems
ADD CONSTRAINT FK_product_id FOREIGN KEY (product_id) REFERENCES products(product_id);