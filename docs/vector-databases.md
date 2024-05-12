# Vector Databases

Disclaimer : I am no ML/AI expert and this document is for my own learning and is no source of truth. Here to find an answer to how can searching be fast and effecient in such large dataset where the similarity has to be found on such large vector :), blows mind, doesnt it.

Vector basically is an array of numbers denoting the weight in each dimension i.e [3,0,-9,0.5,3,1] is 6D or 6 attribute or 6 feature vector. In embedding and ML, the vectors are used to represent large chunk of data into vectors, these vector are generated from pre trained models like hugging face, gpt3 etc. A text is being fed to these models and they spew out an N dimension vector. The dimenion/attribtues of the vector is predefined by the model and depends on how that model has been trained and what data was used to train the mode. Each value in a vector is considered as an attribute or a dimension.

The vector embeddings help to get the similarity between any entity, in this case, semantic searches. The quick easy way to find similarity between vectors is their L2 distance (the typical euclidean distance in n dimension), dot product or cosine projection. using different ways to find similarity between vectors can serve different use cases. but essentially we leverage these kind of searcing among different vectors and the vector DBs somehow optimize this

first start with postgres RDBMS with pgvector, this extension enables vector operations like storage, similartiy searchig etc.
https://github.com/pgvector/pgvector

HNSW
IVFflat
Fiaas (pinecone's blog)
kmeans clustering
kNN


KNN ->  https://medium.com/swlh/k-nearest-neighbor-ca2593d7a3c4
KMEANS -> https://www.youtube.com/watch?v=EItlUEPCIzM
hnsw : https://www.pinecone.io/learn/series/faiss/hnsw/
skip list : 
recall/precision tradeoff : https://medium.com/analytics-vidhya/precision-recall-tradeoff-79e892d43134

these are the algos that help in searching by creating the buckets





* what are vector databases
* Why are they being used
* Scenarios where vector DB vs a pre trained model is used
* How indexes work in vector databases
* Different ways to search vector databases
* Scaling a vector DB
* Open source options


First in line is PGvector, an extension making postgres a vector Database











-----------------------------------------------
https://medium.com/@francesco.cozzolino/top-truly-free-and-open-source-vector-databases-2024-72d179e84277
## Recommendation Systems
1. Collaborative filerting
2. Content based filtering
3. vector databases (difference between a model entity vs vector DB) (https://aws.amazon.com/what-is/vector-databases/)
   seems like overkill (vector DB) (some example : pinecone, qdrant, milvus, weaviate, vespa, redis, https://www.singlestore.com/) https://www.youtube.com/watch?v=ySus5ZS0b94 , https://platform.openai.com/docs/guides/embeddings , https://www.youtube.com/watch?v=ySus5ZS0b94 , https://www.youtube.com/watch?v=1ZIYVNvRVsY
4. semantic search + (what is embedding related to semantic search) (https://www.youtube.com/watch?v=72XgD322wZ8)
5. https://illumin.usc.edu/netflixs-recommendation-systems-entertainment-made-for-you/ (netflix's recommendation system)
6. https://towardsdatascience.com/how-to-build-a-movie-recommendation-system-67e321339109
7. opensearch + vector search (vector search helps with semantic searching) 
8. https://www.pinecone.io/learn/vector-database/

3. model vs an embedding and vector db (model holds data points and so does embedding and vector)
4. well it generates a vector but this vector of number is dependent upon the model it used to get the vector, wo what model exqctly is and how the model got the parameter on which the word should get it's weight/value from?

how can langchain be used to search in vectorDB


two parts to searching
1. semantic searching, user explicitly searching and we giving smeantic results
2. profile based homepage and recommendations

Most crucial part to a vector DB would be to index (Knn algorithm)
if vector db is an overkill for an OTT
how does netflix and other movie recommendation works
movie recommendation basis search on the context as well as user history (2 kinds of recommendation system)

This might be overkill for a movie or an OTT platform as an OTT content already has soo much metadata associated to it.