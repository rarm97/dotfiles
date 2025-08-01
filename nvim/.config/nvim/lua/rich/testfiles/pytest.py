'''
This file is going to be the file mover eventually. 
Goal will be to move files without user prompt first, plugging in and parsing user input is the easy part. 
We need to scan all directories within the directory given and create a flat filelist seperated by filetype. 
In the dest dir we need to create as many folders as 'groups' of file type. Images, office docs, unclassified.
Files then need to be copied into these directories then deleted in the src dir (presumably that's all the mv function would be? Check for efficency. 
We then need to grab meta-data from the files to get date last modified, sort those by month.
'''
def binary_search(arr_in, low, high, search_term):
    midpoint = high - low
    if arr_in[midpoint] < search_term:
        binary_search(arr_in, midpoint, high, search_term)
    if arr_in[midpoint] > search_term:
        binary_search(arr_in, low, midpoint, search_term)
    if arr_in[midpoint] == search_term:
        return midpoint

generate_array = [i for i in range(0, 199, 2)]

searched = binary_search(generate_array, 1,len(generate_array), 188)
print(searched)
