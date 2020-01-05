module ReadStat

using ReadStat_jll

##############################################################################
##
## Import
##
##############################################################################

using DataValues: DataValueVector
using Dates

export ReadStatDataFrame, read_dta, read_sav, read_por, read_sas7bdat

##############################################################################
##
## Julia types that mirror C types
##
##############################################################################

const READSTAT_TYPE_STRING      = Cint(0)
const READSTAT_TYPE_CHAR        = Cint(1)
const READSTAT_TYPE_INT16       = Cint(2)
const READSTAT_TYPE_INT32       = Cint(3)
const READSTAT_TYPE_FLOAT       = Cint(4)
const READSTAT_TYPE_DOUBLE      = Cint(5)
const READSTAT_TYPE_LONG_STRING = Cint(6)

const READSTAT_ERROR_OPEN       = Cint(1)
const READSTAT_ERROR_READ       = Cint(2)
const READSTAT_ERROR_MALLOC     = Cint(3)
const READSTAT_ERROR_USER_ABORT = Cint(4)
const READSTAT_ERROR_PARSE      = Cint(5)

##############################################################################
##
## Pure Julia types
##
##############################################################################

struct ReadStatValue
    union::Int64
    readstat_types_t::Cint
    tag::Cchar
    @static if Sys.iswindows()
        bits::Cuint
    else
        bits::UInt8
    end
end

const Value = ReadStatValue

mutable struct ReadStatDataFrame
    data::Vector{Any}
    headers::Vector{Symbol}
    types::Vector{DataType}
    labels::Vector{String}
    formats::Vector{String}
    storagewidths::Vector{Csize_t}
    measures::Vector{Cint}
    alignments::Vector{Cint}
    val_label_keys::Vector{String}
    val_label_dict::Dict{String, Dict{Any,String}}
    rows::Int
    columns::Int
    filelabel::String
    timestamp::DateTime
    format::Clong
    types_as_int::Vector{Cint}

    ReadStatDataFrame() = 
        new(Any[], Symbol[], DataType[], String[], String[], Csize_t[], Cint[], Cint[],
        String[], Dict{String, Dict{Any,String}}(), 0, 0, "", Dates.unix2datetime(0), 0, Cint[])
end

include("C_interface.jl")

##############################################################################
##
## Julia functions
##
##############################################################################

function handle_info!(obs_count::Cint, var_count::Cint, ds_ptr::Ptr{ReadStatDataFrame})
    ds = unsafe_pointer_to_objref(ds_ptr)
    ds.rows = obs_count
    ds.columns = var_count
    return Cint(0)
end

function handle_metadata!(metadata::Ptr{Nothing}, ds_ptr::Ptr{ReadStatDataFrame})
    ds = unsafe_pointer_to_objref(ds_ptr)
    ds.filelabel = readstat_get_file_label(metadata)
    ds.timestamp = Dates.unix2datetime(readstat_get_modified_time(metadata))
    ds.format = readstat_get_file_format_version(metadata)
    ds.rows = readstat_get_row_count(metadata)
    ds.columns = readstat_get_var_count(metadata)
    return Cint(0)
end

get_name(variable::Ptr{Nothing}) = Symbol(readstat_variable_get_name(variable))

function get_label(var::Ptr{Nothing})
    ptr = ccall((:readstat_variable_get_label, libreadstat), Cstring, (Ptr{Nothing},), var)
    ptr == C_NULL ? "" : unsafe_string(ptr)
end

function get_format(var::Ptr{Nothing})
    ptr = ccall((:readstat_variable_get_format, libreadstat), Cstring, (Ptr{Nothing},), var)
    ptr == C_NULL ? "" : unsafe_string(ptr)
end

function get_type(variable::Ptr{Nothing})
    data_type = readstat_variable_get_type(variable)

    if data_type == READSTAT_TYPE_STRING
        return String
    elseif data_type == READSTAT_TYPE_CHAR
        return Int8
    elseif data_type == READSTAT_TYPE_INT16
        return Int16
    elseif data_type == READSTAT_TYPE_INT32
        return Int32
    elseif data_type == READSTAT_TYPE_FLOAT
        return Float32
    elseif data_type == READSTAT_TYPE_DOUBLE
        return Float64
    end
    return Nothing
end

get_storagewidth(variable::Ptr{Nothing}) = readstat_variable_get_storage_width(variable)

get_measure(variable::Ptr{Nothing}) = readstat_variable_get_measure(variable)

get_alignment(variable::Ptr{Nothing}) = readstat_variable_get_measure(variable)

function handle_variable!(var_index::Cint, variable::Ptr{Nothing}, 
                         val_label::Cstring,  ds_ptr::Ptr{ReadStatDataFrame})
    col = var_index + 1
    ds = unsafe_pointer_to_objref(ds_ptr)

    push!(ds.val_label_keys, (val_label == C_NULL ? "" : unsafe_string(val_label)))
    push!(ds.headers, get_name(variable))
    push!(ds.labels, get_label(variable))
    push!(ds.formats, get_format(variable))
    jtype = get_type(variable)
    push!(ds.types, jtype)
    push!(ds.types_as_int, readstat_variable_get_type(variable))
    push!(ds.data, DataValueVector{jtype}(ds.rows))
    push!(ds.storagewidths, get_storagewidth(variable))
    push!(ds.measures, get_measure(variable))
    push!(ds.alignments, get_alignment(variable))
    
    return Cint(0)
end

function get_type(val::Value)
    data_type = readstat_value_type(val)
    return [String, Int8, Int16, Int32, Float32, Float64, String][data_type + 1]
end

Base.convert(::Type{Int8}, val::Value) = ccall((:readstat_int8_value, libreadstat), Int8, (Value,), val)
Base.convert(::Type{Int16}, val::Value) = ccall((:readstat_int16_value, libreadstat), Int16, (Value,), val)
Base.convert(::Type{Int32}, val::Value) = ccall((:readstat_int32_value, libreadstat), Int32, (Value,), val)
Base.convert(::Type{Float32}, val::Value) = ccall((:readstat_float_value, libreadstat), Float32, (Value,), val)
Base.convert(::Type{Float64}, val::Value) = ccall((:readstat_double_value, libreadstat), Float64, (Value,), val)
function Base.convert(::Type{String}, val::Value)
    ptr = ccall((:readstat_string_value, libreadstat), Cstring, (Value,), val)
    ptr ≠ C_NULL ? unsafe_string(ptr) : ""
end
as_native(val::Value) = convert(get_type(val), val)

function handle_value!(obs_index::Cint, variable::Ptr{Nothing},
                       value::ReadStatValue, ds_ptr::Ptr{ReadStatDataFrame})
    ds = unsafe_pointer_to_objref(ds_ptr)::ReadStatDataFrame
    var_index = readstat_variable_get_index(variable)
    if !readstat_value_is_missing(value, variable)
        if ds.types_as_int[var_index+1]==READSTAT_TYPE_DOUBLE
            readfield!(ds.data[var_index + 1]::DataValueVector{Float64}, obs_index + 1, value)
        elseif ds.types_as_int[var_index+1]==READSTAT_TYPE_INT32
            readfield!(ds.data[var_index + 1]::DataValueVector{Int32}, obs_index + 1, value)
        elseif ds.types_as_int[var_index+1]==READSTAT_TYPE_STRING
            readfield!(ds.data[var_index + 1]::DataValueVector{String}, obs_index + 1, value)
        elseif ds.types_as_int[var_index+1]==READSTAT_TYPE_CHAR
            readfield!(ds.data[var_index + 1]::DataValueVector{Int8}, obs_index + 1, value)
        elseif ds.types_as_int[var_index+1]==READSTAT_TYPE_INT16
            readfield!(ds.data[var_index + 1]::DataValueVector{Int16}, obs_index + 1, value)
        elseif ds.types_as_int[var_index+1]==READSTAT_TYPE_FLOAT
            readfield!(ds.data[var_index + 1]::DataValueVector{Float32}, obs_index + 1, value)
        else        
            readfield!(ds.data[var_index + 1], obs_index + 1, value)
        end
    end

    return Cint(0)
end

function readfield!(dest::DataValueVector{String}, row, val::Value)
    ptr = ccall((:readstat_string_value, libreadstat), Cstring, (Value,), val)
    if ptr ≠ C_NULL
        @inbounds dest[row] = unsafe_string(ptr)
    end
end

function readfield!(dest::DataValueVector{Int8}, row, val::Value)
    @inbounds dest[row] = ccall((:readstat_int8_value, libreadstat), Int8, (Value,), val)
end

function readfield!(dest::DataValueVector{Int16}, row, val::Value)
    @inbounds dest[row] = ccall((:readstat_int16_value, libreadstat), Int16, (Value,), val)
end

function readfield!(dest::DataValueVector{Int32}, row, val::Value)
    @inbounds dest[row] = ccall((:readstat_int32_value, libreadstat), Int32, (Value,), val)
end

function readfield!(dest::DataValueVector{Float64}, row, val::Value)
    @inbounds dest[row] = ccall((:readstat_double_value, libreadstat), Float64, (Value,), val)
end

function readfield!(dest::DataValueVector{Float32}, row, val::Value)
    @inbounds dest[row] = ccall((:readstat_float_value, libreadstat), Float32, (Value,), val)
end

function handle_value_label!(val_labels::Cstring, value::Value, label::Cstring, ds_ptr::Ptr{ReadStatDataFrame})
    val_labels ≠ C_NULL || return Cint(0)
    ds = unsafe_pointer_to_objref(ds_ptr)
    dict = get!(ds.val_label_dict, unsafe_string(val_labels), Dict{Any,String}())
    dict[as_native(value)] = unsafe_string(label)
    
    return Cint(0)
end

function read_data_file(filename::AbstractString, filetype::Val)
    # initialize ds
    ds = ReadStatDataFrame()
    # initialize parser
    parser = Parser()
    # parse
    parse_data_file!(ds, parser, filename, filetype)
    # return dataframe instead of ReadStatDataFrame
    return ds
end

function Parser()
    parser = ccall((:readstat_parser_init, libreadstat), Ptr{Nothing}, ())
    info_fxn = @cfunction(handle_info!, Cint, (Cint, Cint, Ptr{ReadStatDataFrame}))
    meta_fxn = @cfunction(handle_metadata!, Cint, (Ptr{Nothing}, Ptr{ReadStatDataFrame}))
    var_fxn = @cfunction(handle_variable!, Cint, (Cint, Ptr{Nothing}, Cstring,  Ptr{ReadStatDataFrame}))
    val_fxn = @cfunction(handle_value!, Cint, (Cint, Ptr{Nothing}, ReadStatValue, Ptr{ReadStatDataFrame}))
    label_fxn = @cfunction(handle_value_label!, Cint, (Cstring, Value, Cstring, Ptr{ReadStatDataFrame}))
    ccall((:readstat_set_metadata_handler, libreadstat), Int, (Ptr{Nothing}, Ptr{Nothing}), parser, meta_fxn)
    ccall((:readstat_set_variable_handler, libreadstat), Int, (Ptr{Nothing}, Ptr{Nothing}), parser, var_fxn)
    ccall((:readstat_set_value_handler, libreadstat), Int, (Ptr{Nothing}, Ptr{Nothing}), parser, val_fxn)
    ccall((:readstat_set_value_label_handler, libreadstat), Int, (Ptr{Nothing}, Ptr{Nothing}), parser, label_fxn)
    return parser
end  

function parse_data_file!(ds::ReadStatDataFrame, parser::Ptr{Nothing}, filename::AbstractString, filetype::Val)
    retval = readstat_parse(filename, filetype, parser, ds)
    readstat_parser_free(parser)
    retval == 0 ||  error("Error parsing $filename: $retval")
end

read_dta(filename::AbstractString) = read_data_file(filename, Val(:dta))
read_sav(filename::AbstractString) = read_data_file(filename, Val(:sav))
read_por(filename::AbstractString) = read_data_file(filename, Val(:por))
read_sas7bdat(filename::AbstractString) = read_data_file(filename, Val(:sas7bdat))

end #module ReadStat
